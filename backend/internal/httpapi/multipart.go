package httpapi

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"strings"
	"unicode"
	"unicode/utf16"
	"unicode/utf8"
)

// multipart の本文の読み方は、Java 版の Tomcat 11.0.27 の multipart の部品を写した。
// 写した元は、org.apache.tomcat.util.http.fileupload の MultipartStream、FileUploadBase、ParameterParser、RFC2231Utility、
// impl.FileItemIteratorImpl、impl.FileItemStreamImpl、util.mime.MimeUtility、util.mime.QuotedPrintableDecoder である
// (https://github.com/apache/tomcat/tree/11.0.27/java/org/apache/tomcat/util/http/fileupload)。
// Go の標準の mime/multipart は、部分の見出しに制御文字があると本文の全体を誤りにし、Tomcat は読む。
// research.md の試作の記録の P4 に、違いを書いた。

// multipart の本文を読むときの上限は、Java 版の Spring Boot 4.1.2 が Tomcat に渡す値である。
const (
	// multipartMaxPartHeaderSize は、1つの部分の見出しのバイト数の上限である。server.tomcat.max-part-header-size の既定の 512B にあたる
	multipartMaxPartHeaderSize = 512
	// multipartMaxPartCount は、名前を持つ部分の数の上限である。server.tomcat.max-part-count の既定の 50 にあたる
	multipartMaxPartCount = 50
	// multipartMaxFileSize は、1つの部分の中身のバイト数の上限である。application.yaml の spring.servlet.multipart.max-file-size の 2MB にあたる
	multipartMaxFileSize = 2097152
	// tomcatBufferSize は、Tomcat の MultipartStream の DEFAULT_BUFSIZE である。境界の文字列の長さの上限を決める
	tomcatBufferSize = 4096
)

// tomcatBoundaryPrefix は、部分の中身の終わりを示す区切りの、境界の文字列の前に付く4バイトである。
var tomcatBoundaryPrefix = []byte("\r\n--")

// tomcatHeaderSeparator は、部分の見出しの終わりを示す4バイトである。
var tomcatHeaderSeparator = []byte("\r\n\r\n")

var errMultipart = errors.New("multipart の本文を読めません")

// multipartHeaders は、部分の見出しである。見出しの名前を ASCII の小文字にした値を鍵にし、同じ名前の値を現れた順に持つ。
// Tomcat の FileItemHeadersImpl にあたる。
type multipartHeaders map[string][]string

// get は、名前が name の見出しのうち、最初の値を返す。Tomcat の FileItemHeadersImpl.getHeader にあたる。
func (h multipartHeaders) get(name string) (string, bool) {
	v := h[asciiLower(name)]
	if len(v) == 0 {
		return "", false
	}
	return v[0], true
}

// multipartPart は、multipart の本文の1つの部分である。Tomcat の FileItem にあたる。
type multipartPart struct {
	// FieldName は、Tomcat が読んだ部分の名前である。Spring の MultipartFile と文字の値は、この名前で引かれる
	FieldName string
	// FileName と HasFileName は、Tomcat の FileUploadBase.getFileName が読んだファイルの名前である。
	// Content-Disposition に filename の項目があれば、値が無くても HasFileName が真になる
	FileName    string
	HasFileName bool
	Headers     multipartHeaders
	Body        []byte
}

// parseMultipart は、要求の Content-Type と本文から、名前を持つ部分を順に取り出す。
// Tomcat の FileUploadBase.parseRequest と同じ規則で読み、Tomcat が例外を投げる本文には誤りを返す。
//
// Tomcat は、次の本文を誤りにせず、そこまでに読んだ部分だけを返す。
//   - 境界の文字列が1つも無い本文と、最後の境界のあとで終わる本文
//   - 境界の文字列のあとに、改行でも -- でもない字が続く本文
//
// Tomcat は、2つ目からの部分も、前置きを読み飛ばす処理(MultipartStream.skipPreamble)で探す。
// この処理は境界のあとの崩れを誤りにしないので、2つ目からの部分の前の崩れも誤りにならない。
func parseMultipart(contentType string, body []byte) ([]multipartPart, error) {
	// Tomcat は、要求の見出しの値を ISO-8859-1 で文字列にする
	ct := latin1Runes(contentType)
	if !strings.HasPrefix(asciiLower(string(ct)), "multipart/") {
		return nil, fmt.Errorf("%w: Content-Type が multipart でない", errMultipart)
	}
	boundary, ok, err := tomcatBoundary(ct)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, fmt.Errorf("%w: 境界の文字列が無い", errMultipart)
	}
	if len(boundary)+len(tomcatBoundaryPrefix)+1 > tomcatBufferSize {
		return nil, fmt.Errorf("%w: 境界の文字列が長すぎる", errMultipart)
	}
	s := &tomcatStream{data: body}
	s.setBoundary(boundary)

	var parts []multipartPart
	// nestedField は、multipart/mixed の部分の中を読んでいるときの、外の部分の名前である
	nested := false
	nestedField := ""
	for {
		next, err := s.skipPreamble()
		if err != nil {
			return nil, err
		}
		if !next {
			if !nested {
				return parts, nil
			}
			// 中の multipart が終わったので、外の境界の文字列に戻す
			s.setBoundary(boundary)
			nested = false
			continue
		}
		headers, err := s.readHeaders()
		if err != nil {
			return nil, err
		}
		if !nested {
			// Tomcat は、外の部分では、Content-Disposition が form-data で始まるときだけ項目を読む
			params, err := tomcatDisposition(headers, false)
			if err != nil {
				return nil, err
			}
			if fieldName, hasFieldName := tomcatFieldName(params); hasFieldName {
				if sub, ok := headers.get("content-type"); ok && strings.HasPrefix(asciiLower(sub), "multipart/mixed") {
					subBoundary, ok, err := tomcatBoundary([]rune(sub))
					if err != nil {
						return nil, err
					}
					if !ok {
						return nil, fmt.Errorf("%w: multipart/mixed の部分に境界の文字列が無い", errMultipart)
					}
					if len(subBoundary) != len(boundary) {
						return nil, fmt.Errorf("%w: multipart/mixed の部分の境界の文字列の長さが外と違う", errMultipart)
					}
					s.setBoundary(subBoundary)
					nested = true
					nestedField = fieldName
					continue
				}
				// Tomcat はファイルの名前を読むときに Content-Disposition をもう一度読むが、同じ項目を同じ読み方で読むので、結果は変わらない
				fileName, hasFileName := tomcatFileName(params)
				part, err := s.readItem(len(parts), fieldName, fileName, hasFileName, headers)
				if err != nil {
					return nil, err
				}
				parts = append(parts, part)
				continue
			}
		} else {
			// multipart/mixed の中の部分では、Content-Disposition が form-data か attachment で始まるときに項目を読む
			params, err := tomcatDisposition(headers, true)
			if err != nil {
				return nil, err
			}
			if fileName, hasFileName := tomcatFileName(params); hasFileName {
				part, err := s.readItem(len(parts), nestedField, fileName, hasFileName, headers)
				if err != nil {
					return nil, err
				}
				parts = append(parts, part)
				continue
			}
		}
		// 名前の無い部分と、multipart/mixed の中のファイルの名前の無い部分は、中身を読み飛ばす
		if _, err := s.readBody(); err != nil {
			return nil, err
		}
	}
}

// tomcatStream は、Tomcat の MultipartStream にあたる。本文の全体を持ち、読んだ位置 head を進める。
type tomcatStream struct {
	data []byte
	head int
	// boundary は、部分の中身の終わりを示す区切りである。tomcatBoundaryPrefix と境界の文字列をつないだもの
	boundary []byte
	// broken は、境界の文字列のすぐあとで本文が終わったことを示す。
	// Tomcat の MultipartStream は、このとき読み込みの位置を壊したまま残し、次に区切りを探すと例外を投げる
	broken bool
}

// setBoundary は、境界の文字列を変える。Tomcat の MultipartStream.setBoundary にあたる。
func (s *tomcatStream) setBoundary(boundary []byte) {
	s.boundary = append(append([]byte{}, tomcatBoundaryPrefix...), boundary...)
}

// skipPreamble は、Tomcat の MultipartStream.skipPreamble にあたる。先頭の改行を除いた区切りを探して、その前を読み飛ばし、
// 区切りのあとの2バイトを見る。改行(CR LF か LF だけ)なら次の部分があるとして真を返し、-- かほかの字なら偽を返す。
// 区切りが見つからないときと、区切りのすぐあとで本文が終わるときも、偽を返す。
func (s *tomcatStream) skipPreamble() (bool, error) {
	if s.broken {
		return false, fmt.Errorf("%w: 本文の終わりのあとをさらに読もうとした", errMultipart)
	}
	sep := s.boundary[2:]
	i := bytes.Index(s.data[s.head:], sep)
	if i < 0 {
		// Tomcat は、区切りの長さぶんの最後のバイトを、次に区切りを探すために読み込みの場所に残す
		keep := min(len(s.boundary), len(s.data)-s.head)
		s.head = len(s.data) - keep
		return false, nil
	}
	s.head += i + len(sep)
	if s.head == len(s.data) {
		s.broken = true
		return false, nil
	}
	b0 := s.data[s.head]
	s.head++
	if b0 == '\n' {
		return true, nil
	}
	if s.head == len(s.data) {
		s.broken = true
		return false, nil
	}
	b1 := s.data[s.head]
	s.head++
	return b0 == '\r' && b1 == '\n', nil
}

// readHeaders は、Tomcat の MultipartStream.readHeaders と FileUploadBase.getParsedHeaders にあたる。
// CR LF CR LF までのバイトを読み、見出しに分けて返す。
// Tomcat は、4バイトの並びを、食い違ったら最初から数え直す素朴な方法で探す。そのため、CR CR LF CR LF のような並びでは終わりを見逃す。
func (s *tomcatStream) readHeaders() (multipartHeaders, error) {
	start := s.head
	matched := 0
	for matched < len(tomcatHeaderSeparator) {
		if s.head == len(s.data) {
			return nil, fmt.Errorf("%w: 部分の見出しの途中で本文が終わった", errMultipart)
		}
		b := s.data[s.head]
		s.head++
		if s.head-start > multipartMaxPartHeaderSize {
			return nil, fmt.Errorf("%w: 部分の見出しが %d バイトを超えた", errMultipart, multipartMaxPartHeaderSize)
		}
		if b == tomcatHeaderSeparator[matched] {
			matched++
		} else {
			matched = 0
		}
	}
	// Spring Boot は要求の文字コードを UTF-8 にするので、Tomcat は部分の見出しを UTF-8 で文字列にする
	return parsePartHeaders(decodeJDKUTF8(s.data[start:s.head]))
}

// readBody は、部分の中身を、区切りの前まで返す。Tomcat の MultipartStream.ItemInputStream にあたる。
// 区切りが無いまま本文が終われば、誤りを返す。
func (s *tomcatStream) readBody() ([]byte, error) {
	i := bytes.Index(s.data[s.head:], s.boundary)
	if i < 0 {
		return nil, fmt.Errorf("%w: 部分の中身の途中で本文が終わった", errMultipart)
	}
	b := s.data[s.head : s.head+i]
	s.head += i
	return b, nil
}

// readItem は、名前を持つ部分を1つ読む。Tomcat の FileItemStreamImpl の作り方と、FileUploadBase.parseRequest の検査の順にあたる。
// count は、それまでに読んだ名前を持つ部分の数である。
func (s *tomcatStream) readItem(count int, fieldName, fileName string, hasFileName bool, headers multipartHeaders) (multipartPart, error) {
	if cl, ok := headers.get("content-length"); ok {
		if n, ok := javaParseLong(cl); ok && n > multipartMaxFileSize {
			return multipartPart{}, fmt.Errorf("%w: 部分の Content-Length が上限を超えた", errMultipart)
		}
	}
	if count == multipartMaxPartCount {
		return multipartPart{}, fmt.Errorf("%w: 部分が %d を超えた", errMultipart, multipartMaxPartCount)
	}
	if hasFileName && strings.ContainsRune(fileName, 0) {
		return multipartPart{}, fmt.Errorf("%w: ファイルの名前に NUL がある", errMultipart)
	}
	body, err := s.readBody()
	if err != nil {
		return multipartPart{}, err
	}
	if len(body) > multipartMaxFileSize {
		return multipartPart{}, fmt.Errorf("%w: 部分の中身が上限を超えた", errMultipart)
	}
	return multipartPart{FieldName: fieldName, FileName: fileName, HasFileName: hasFileName, Headers: headers, Body: body}, nil
}

// parsePartHeaders は、Tomcat の FileUploadBase.getParsedHeaders にあたる。
// 行の頭が空白かタブの行は、前の行の続きとして空白1つでつなぐ。: の無い行は捨てる。見出しの名前と値の前後の空白と制御文字は除く。
func parsePartHeaders(headerPart string) (multipartHeaders, error) {
	headers := multipartHeaders{}
	n := len(headerPart)
	start := 0
	for {
		end, err := tomcatEndOfLine(headerPart, start)
		if err != nil {
			return nil, err
		}
		if start == end {
			return headers, nil
		}
		var header strings.Builder
		header.WriteString(headerPart[start:end])
		start = end + 2
		for start < n {
			nonWs := start
			for nonWs < n && (headerPart[nonWs] == ' ' || headerPart[nonWs] == '\t') {
				nonWs++
			}
			if nonWs == start {
				break
			}
			end, err = tomcatEndOfLine(headerPart, nonWs)
			if err != nil {
				return nil, err
			}
			header.WriteByte(' ')
			header.WriteString(headerPart[nonWs:end])
			start = end + 2
		}
		line := header.String()
		colon := strings.IndexByte(line, ':')
		if colon < 0 {
			continue
		}
		name := asciiLower(javaTrim(line[:colon]))
		headers[name] = append(headers[name], javaTrim(line[colon+1:]))
	}
}

// tomcatEndOfLine は、Tomcat の FileUploadBase.parseEndOfLine にあたる。from から探して、LF が続く最初の CR の位置を返す。
func tomcatEndOfLine(s string, from int) (int, error) {
	index := from
	for {
		i := strings.IndexByte(s[index:], '\r')
		if i < 0 || index+i+1 >= len(s) {
			return 0, fmt.Errorf("%w: 部分の見出しが空の行で終わっていない", errMultipart)
		}
		if s[index+i+1] == '\n' {
			return index + i, nil
		}
		index += i + 1
	}
}

// tomcatBoundary は、Tomcat の FileUploadBase.getBoundary にあたる。Content-Type の boundary の項目の値を ISO-8859-1 のバイトにする。
// 項目は、; と , のうち先に現れるほうで区切る。
func tomcatBoundary(contentType []rune) ([]byte, bool, error) {
	sep := ';'
	idx := len(contentType)
	for _, c := range []rune{';', ','} {
		for i, r := range contentType {
			if r == c {
				if i < idx {
					idx = i
					sep = c
				}
				break
			}
		}
	}
	params, err := tomcatParseParams(contentType, sep)
	if err != nil {
		return nil, false, err
	}
	p, ok := params["boundary"]
	if !ok || !p.hasValue {
		return nil, false, nil
	}
	// ISO-8859-1 で表せない字は ? にする
	b := make([]byte, 0, len(p.value))
	for _, r := range p.value {
		if r <= 0xFF {
			b = append(b, latin1Byte(r))
		} else {
			b = append(b, '?')
		}
	}
	return b, true, nil
}

// tomcatDisposition は、Tomcat の FileUploadBase.getFieldName と getFileName が Content-Disposition の項目を読む処理にあたる。
// Content-Disposition が form-data で始まれば、項目を読む。allowAttachment なら、attachment で始まるときも読む。
// 読まないときは、nil を返す。
func tomcatDisposition(h multipartHeaders, allowAttachment bool) (map[string]tomcatParam, error) {
	cd, ok := h.get("content-disposition")
	if !ok {
		return nil, nil
	}
	lower := asciiLower(cd)
	if !strings.HasPrefix(lower, "form-data") && (!allowAttachment || !strings.HasPrefix(lower, "attachment")) {
		return nil, nil
	}
	return tomcatParseParams([]rune(cd), ';')
}

// tomcatFieldName は、Tomcat の FileUploadBase.getFieldName にあたる。
// name の項目に値があれば、その値の前後の空白と制御文字を除いて返す。
func tomcatFieldName(params map[string]tomcatParam) (string, bool) {
	p, ok := params["name"]
	if !ok || !p.hasValue {
		return "", false
	}
	return javaTrim(p.value), true
}

// tomcatFileName は、Tomcat の FileUploadBase.getFileName にあたる。
// filename の項目があれば、値の前後の空白と制御文字を除いて返す。filename の項目に値が無ければ、空の名前を返す。
func tomcatFileName(params map[string]tomcatParam) (string, bool) {
	p, ok := params["filename"]
	if !ok {
		return "", false
	}
	return javaTrim(p.value), true
}

// tomcatParam は、Tomcat の ParameterParser が読んだ項目の値である。hasValue が偽なら、値は null である。
type tomcatParam struct {
	value    string
	hasValue bool
}

// tomcatParseParams は、Tomcat の ParameterParser.parse にあたる。項目の名前を ASCII の小文字にした値を鍵にする。
// 同じ鍵の項目が2つあれば、あとのほうが残る。
// 項目の名前が * で終われば、* を除いた名前にし、値を RFC 2231 の書き方として解く。そうでなければ、値を RFC 2047 の書き方として解く。
func tomcatParseParams(chars []rune, sep rune) (map[string]tomcatParam, error) {
	params := map[string]tomcatParam{}
	pos := 0
	for pos < len(chars) {
		i1 := pos
		for pos < len(chars) && chars[pos] != '=' && chars[pos] != sep {
			pos++
		}
		name, hasName := tomcatToken(chars, i1, pos, false)
		var p tomcatParam
		if pos < len(chars) && chars[pos] == '=' {
			pos++
			i1 = pos
			quoted := false
			escaped := false
			for pos < len(chars) {
				c := chars[pos]
				if !quoted && c == sep {
					break
				}
				if !escaped && c == '"' {
					quoted = !quoted
				}
				escaped = !escaped && c == '\\'
				pos++
			}
			if v, ok := tomcatToken(chars, i1, pos, true); ok {
				decoded, err := tomcatDecodeParamValue(name, hasName, v)
				if err != nil {
					return nil, err
				}
				p = tomcatParam{value: decoded, hasValue: true}
			}
		}
		if pos < len(chars) && chars[pos] == sep {
			pos++
		}
		if hasName {
			params[asciiLower(strings.TrimSuffix(name, "*"))] = p
		}
	}
	return params, nil
}

// tomcatToken は、Tomcat の ParameterParser.getToken にあたる。chars[i1:i2] の前後の空白を除き、quoted なら両端の " を1つずつ除く。
// 残りが空なら、偽を返す。
func tomcatToken(chars []rune, i1, i2 int, quoted bool) (string, bool) {
	for i1 < i2 && javaIsWhitespace(chars[i1]) {
		i1++
	}
	for i2 > i1 && javaIsWhitespace(chars[i2-1]) {
		i2--
	}
	if quoted && i2-i1 >= 2 && chars[i1] == '"' && chars[i2-1] == '"' {
		i1++
		i2--
	}
	if i2 > i1 {
		return string(chars[i1:i2]), true
	}
	return "", false
}

// javaIsWhitespace は、Java の Character.isWhitespace にあたる。
// 空白の区切りの字のうち、改行しない空白(U+00A0、U+2007、U+202F)は空白にしない。U+0085 も空白にしない。
func javaIsWhitespace(r rune) bool {
	switch {
	case r >= 0x09 && r <= 0x0D, r >= 0x1C && r <= 0x20:
		return true
	case r == 0x1680, r >= 0x2000 && r <= 0x2006, r >= 0x2008 && r <= 0x200A:
		return true
	case r == 0x2028, r == 0x2029, r == 0x205F, r == 0x3000:
		return true
	}
	return false
}

// tomcatDecodeParamValue は、ParameterParser が項目の値を解く処理にあたる。
// Tomcat が UnsupportedEncodingException で解くのをやめる値は、解かずにそのまま返す。
func tomcatDecodeParamValue(name string, hasName bool, value string) (string, error) {
	var decoded string
	var raw bool
	var err error
	if hasName && strings.HasSuffix(name, "*") {
		decoded, raw, err = tomcatDecodeRFC2231(value)
	} else {
		decoded, raw, err = tomcatDecodeRFC2047(value)
	}
	if err != nil {
		return "", err
	}
	if raw {
		return value, nil
	}
	return decoded, nil
}

// tomcatDecodeRFC2231 は、Tomcat の RFC2231Utility.decodeText にあたる。文字コード'言語'%XX の形の値を解く。
// ' が2つ無ければ、値をそのまま返す。raw が真なら、Tomcat は値を解かずに使う。
func tomcatDecodeRFC2231(text string) (string, bool, error) {
	first := strings.IndexByte(text, '\'')
	if first < 0 {
		return text, false, nil
	}
	second := strings.IndexByte(text[first+1:], '\'')
	if second < 0 {
		return text, false, nil
	}
	return decodeWithJavaCharsetName(text[:first], tomcatFromHex(text[first+1+second+1:]))
}

// rfc2231HexValues は、Tomcat の RFC2231Utility の HEX_DECODE である。16進の字でない字の値は0である。
var rfc2231HexValues = func() [128]byte {
	var t [128]byte
	for c := byte('0'); c <= '9'; c++ {
		t[c] = c - '0'
	}
	for c := byte('A'); c <= 'F'; c++ {
		t[c] = c - 'A' + 10
		t[c+'a'-'A'] = c - 'A' + 10
	}
	return t
}()

// tomcatFromHex は、Tomcat の RFC2231Utility.fromHex にあたる。Java の char ごと(UTF-16 の単位ごと)に読む。
// %XX はバイトにし、ほかの字は char の下の8ビットにする。16進の字でない字は0として読み、最後の2字に足りない % のところで読み終える。
func tomcatFromHex(text string) []byte {
	units := utf16.Encode([]rune(text))
	out := make([]byte, 0, len(units))
	var low [2]byte
	for i := 0; i < len(units); {
		c := units[i]
		i++
		if c == '%' {
			if i > len(units)-2 {
				break
			}
			b1 := rfc2231HexValues[units[i]&0x7f]
			b2 := rfc2231HexValues[units[i+1]&0x7f]
			i += 2
			out = append(out, b1<<4|b2)
			continue
		}
		binary.LittleEndian.PutUint16(low[:], c)
		out = append(out, low[0])
	}
	return out
}

// tomcatDecodeRFC2047 は、Tomcat の MimeUtility.decodeText にあたる。空白で区切った語のうち =? で始まる語を、RFC 2047 の書き方として解く。
// 解いた語どうしの間の空白は除く。最後の空白も除く。raw が真なら、Tomcat は値を解かずに使う。
func tomcatDecodeRFC2047(text string) (string, bool, error) {
	if !strings.Contains(text, "=?") {
		return text, false, nil
	}
	isLWS := func(c byte) bool { return c == ' ' || c == '\t' || c == '\r' || c == '\n' }
	var out strings.Builder
	startWS, endWS := -1, -1
	previousEncoded := false
	offset := 0
	for offset < len(text) {
		if isLWS(text[offset]) {
			startWS = offset
			for offset < len(text) {
				if !isLWS(text[offset]) {
					endWS = offset
					break
				}
				offset++
			}
			continue
		}
		wordStart := offset
		for offset < len(text) && !isLWS(text[offset]) {
			offset++
		}
		word := text[wordStart:offset]
		if strings.HasPrefix(word, "=?") {
			decoded, result, err := tomcatDecodeWord(word)
			if err != nil {
				return "", false, err
			}
			switch result {
			case wordRaw:
				return "", true, nil
			case wordDecoded:
				if !previousEncoded && startWS != -1 {
					out.WriteString(text[startWS:endWS])
					startWS = -1
				}
				previousEncoded = true
				out.WriteString(decoded)
				continue
			}
		}
		if startWS != -1 {
			out.WriteString(text[startWS:endWS])
			startWS = -1
		}
		previousEncoded = false
		out.WriteString(word)
	}
	return out.String(), false, nil
}

// wordResult は、RFC 2047 の書き方の1つの語を解いた結果である。
type wordResult int

const (
	// wordDecoded は、語を解けたことを示す
	wordDecoded wordResult = iota
	// wordNotEncoded は、語が RFC 2047 の形でないことを示す。Tomcat の ParseException にあたり、語をそのまま使う
	wordNotEncoded
	// wordRaw は、Tomcat が UnsupportedEncodingException を投げることを示す。値の全体を解かずに使う
	wordRaw
)

// mimeToJavaCharsets は、Tomcat の MimeUtility の MIME2JAVA である。us-ascii は ISO-8859-1 として解く。
var mimeToJavaCharsets = map[string]string{
	"iso-2022-cn": "ISO2022CN", "iso-2022-kr": "ISO2022KR", "utf-8": "UTF8", "utf8": "UTF8",
	"ja_jp.iso2022-7": "ISO2022JP", "ja_jp.eucjp": "EUCJIS", "euc-kr": "KSC5601", "euckr": "KSC5601",
	"us-ascii": "ISO-8859-1", "x-us-ascii": "ISO-8859-1",
}

// tomcatDecodeWord は、Tomcat の MimeUtility.decodeWord にあたる。=?文字コード?B か Q?中身?= の語を解く。
func tomcatDecodeWord(word string) (string, wordResult, error) {
	charsetEnd := strings.IndexByte(word[2:], '?')
	if charsetEnd < 0 {
		return "", wordNotEncoded, nil
	}
	charsetEnd += 2
	encodingEnd := strings.IndexByte(word[charsetEnd+1:], '?')
	if encodingEnd < 0 {
		return "", wordNotEncoded, nil
	}
	encodingEnd += charsetEnd + 1
	textEnd := strings.Index(word[encodingEnd+1:], "?=")
	if textEnd < 0 {
		return "", wordNotEncoded, nil
	}
	encodedText := word[encodingEnd+1 : encodingEnd+1+textEnd]
	if encodedText == "" {
		return "", wordDecoded, nil
	}
	var data []byte
	switch word[charsetEnd+1 : encodingEnd] {
	case "B":
		// Java の Base64 の誤りは IllegalArgumentException なので、Tomcat は本文の全体を読めない。
		// ASCII でない字は、Java も Go も Base64 の字でないので、どちらも誤りになる
		d, err := decodeJavaBase64(encodedText)
		if err != nil {
			return "", wordDecoded, fmt.Errorf("%w: %w", errMultipart, err)
		}
		data = d
	case "Q":
		// Java は、ASCII でない字を1字ずつ ? にしてから解く
		ascii := make([]byte, 0, len(encodedText))
		for _, r := range encodedText {
			if r < 0x80 {
				// ASCII の字の UTF-8 は、その字の1バイトである
				ascii = utf8.AppendRune(ascii, r)
			} else {
				ascii = append(ascii, '?')
			}
		}
		d, ok := tomcatDecodeQuotedPrintable(ascii)
		if !ok {
			return "", wordRaw, nil
		}
		data = d
	default:
		return "", wordRaw, nil
	}
	charset := javaRootLowerForCharset(word[2:charsetEnd])
	if mapped, ok := mimeToJavaCharsets[charset]; ok {
		charset = mapped
	}
	decoded, raw, err := decodeWithJavaCharsetName(charset, data)
	if err != nil {
		return "", wordDecoded, err
	}
	if raw {
		return "", wordRaw, nil
	}
	return decoded, wordDecoded, nil
}

// javaRootLowerForCharset は、文字コードの名前に Java の toLowerCase(Locale.ROOT) をかけた結果を、名前の判定に要る範囲で写す。
// ASCII の大文字と、ケルビンの記号(U+212A、k になる)を小文字にする。ほかの字は、小文字にしても ASCII にならないので、
// そのままでも、文字コードの名前として誤っているという判定は変わらない。
func javaRootLowerForCharset(s string) string {
	return strings.Map(func(r rune) rune {
		switch {
		case r >= 'A' && r <= 'Z':
			return r + 'a' - 'A'
		case r == 0x212A:
			return 'k'
		}
		return r
	}, s)
}

// tomcatDecodeQuotedPrintable は、Tomcat の QuotedPrintableDecoder.decode にあたる。_ を空白にし、=XX をバイトにし、= CR LF を除く。
// 誤った形なら偽を返す。Tomcat は、このとき UnsupportedEncodingException を投げる。
func tomcatDecodeQuotedPrintable(data []byte) ([]byte, bool) {
	out := make([]byte, 0, len(data))
	for off := 0; off < len(data); {
		ch := data[off]
		off++
		switch ch {
		case '_':
			out = append(out, ' ')
		case '=':
			if off+1 >= len(data) {
				return nil, false
			}
			b1, b2 := data[off], data[off+1]
			off += 2
			if b1 == '\r' {
				if b2 != '\n' {
					return nil, false
				}
				continue
			}
			c1, ok1 := hexDigit(b1)
			c2, ok2 := hexDigit(b2)
			if !ok1 || !ok2 {
				return nil, false
			}
			out = append(out, c1<<4|c2)
		default:
			out = append(out, ch)
		}
	}
	return out, true
}

// decodeWithJavaCharsetName は、Java の new String(bytes, charsetName) にあたる。
// 名前が文字コードの名前の形でなければ、Java は UnsupportedEncodingException を投げるので、raw を真にする。
// 名前が UTF-8 と ISO-8859-1 と US-ASCII とその別名のどれでもなければ、誤りを返す。JDK が読めても Go 版は読まない(research.md の P4 の節)。
func decodeWithJavaCharsetName(name string, data []byte) (string, bool, error) {
	if !javaCharsetNameLegal(name) {
		return "", true, nil
	}
	cs, ok := jdkCharsetNames[asciiLower(name)]
	if !ok {
		return "", false, fmt.Errorf("%w: 文字コード %q を読まない", errMultipart, name)
	}
	return cs.decode(data), false, nil
}

// javaCharsetNameLegal は、JDK 21 の Charset.checkName にあたる。名前は空でなく、ASCII の英字と数字で始まり、
// 2字目からは英字と数字と - + : _ . だけを使う。
func javaCharsetNameLegal(name string) bool {
	if name == "" {
		return false
	}
	for i := 0; i < len(name); i++ {
		c := name[i]
		switch {
		case c >= 'A' && c <= 'Z', c >= 'a' && c <= 'z', c >= '0' && c <= '9':
		case i > 0 && (c == '-' || c == '+' || c == ':' || c == '_' || c == '.'):
		default:
			return false
		}
	}
	return true
}

// latin1Byte は、U+0000 から U+00FF までの字を、ISO-8859-1 の1バイトにする。
// U+0080 からの字の UTF-8 は2バイトで、1バイト目の下の2ビットと2バイト目の下の6ビットが、ISO-8859-1 のバイトになる。
func latin1Byte(r rune) byte {
	var buf [utf8.UTFMax]byte
	if utf8.EncodeRune(buf[:], r) == 1 {
		return buf[0]
	}
	return (buf[0]&0x03)<<6 | buf[1]&0x3F
}

// latin1Runes は、バイト列を ISO-8859-1 として1バイトずつ字にする。Tomcat は、要求の見出しの値をこの規則で文字列にする。
func latin1Runes(s string) []rune {
	r := make([]rune, len(s))
	for i := 0; i < len(s); i++ {
		r[i] = rune(s[i])
	}
	return r
}

// javaParseLong は、Java の Long.parseLong にあたる。読めなければ偽を返す。
// Java は、char ごとに Character.digit で数字を読むので、全角の数字のような BMP の10進の数字も読み、BMP の外の数字は読まない。
func javaParseLong(s string) (int64, bool) {
	units := utf16.Encode([]rune(s))
	if len(units) == 0 {
		return 0, false
	}
	i := 0
	negative := false
	if units[0] == '-' || units[0] == '+' {
		negative = units[0] == '-'
		i = 1
		if len(units) == 1 {
			return 0, false
		}
	}
	// 負の値で積み上げると、Long.MIN_VALUE まで桁あふれせずに読める
	const minInt64 = -1 << 63
	limit := int64(-(1<<63 - 1))
	if negative {
		limit = minInt64
	}
	var v int64
	for ; i < len(units); i++ {
		d, ok := javaDecimalDigit(rune(units[i]))
		if !ok {
			return 0, false
		}
		if v < limit/10 {
			return 0, false
		}
		v *= 10
		if v < limit+d {
			return 0, false
		}
		v -= d
	}
	if negative {
		return v, true
	}
	return -v, true
}

// javaDecimalDigit は、Java の Character.digit(char, 10) にあたる。Unicode の10進の数字は、0 から 9 の10字が並んで置かれるので、
// 並びの始まりからの位置で値を決める。
func javaDecimalDigit(r rune) (int64, bool) {
	if !unicode.Is(unicode.Nd, r) {
		return 0, false
	}
	start := r
	for start > 0 && unicode.Is(unicode.Nd, start-1) {
		start--
	}
	return int64((r - start) % 10), true
}
