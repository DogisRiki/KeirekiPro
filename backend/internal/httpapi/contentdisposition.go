package httpapi

import (
	"errors"
	"fmt"
	"regexp"
	"strings"
	"unicode/utf8"
)

// contentDisposition は、multipart の部分の Content-Disposition の見出しを読んだ結果である。
// Java 版の Spring の ContentDisposition が持つ値のうち、Java 版が使う種類と名前とファイルの名前を持つ。
// Java の null は、HasName と HasFileName を偽にして表す。
type contentDisposition struct {
	Type        string
	Name        string
	HasName     bool
	FileName    string
	HasFileName bool
}

// errContentDisposition は、Spring の ContentDisposition.parse が例外を投げる見出しのときに返す誤りである。
var errContentDisposition = errors.New("部分の Content-Disposition を読めません")

// rfc2047Base64 と rfc2047QuotedPrintable は、Spring の BASE64_ENCODED_PATTERN と QUOTED_PRINTABLE_ENCODED_PATTERN を写したものである。
// Java の [0-9a-zA-Z-_] の - は、範囲のあとにあるので字の - である。Go では、同じ字の集まりを [0-9a-zA-Z_-] と書く。
var (
	rfc2047Base64          = regexp.MustCompile(`=\?([0-9a-zA-Z_-]+)\?B\?([+/0-9a-zA-Z]+=*)\?=`)
	rfc2047QuotedPrintable = regexp.MustCompile(`=\?([0-9a-zA-Z_-]+)\?Q\?([!->@-~]+)\?=`)
)

// parseContentDisposition は、見出しの値を、Java 版の Spring 7.0.10 の ContentDisposition.parse と同じ規則で読む。
// Java 版は、部分のファイルの名前をこの規則で読む。Go の標準の mime.ParseMediaType とは、
// RFC 2047 の書き方を解くことと、逆スラッシュの扱いと、最後の / のあとだけを名前にしないことが違う(research.md の試作の記録の P4)。
//
// 写した元は、Spring 7.0.10 の org.springframework.http.ContentDisposition の parse と、それが呼ぶ tokenize などの関数である
// (https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-web/src/main/java/org/springframework/http/ContentDisposition.java)。
// 見出しの値は、Java 版の Tomcat と同じく、部分の見出しのバイト列を decodeJDKUTF8 で文字列にしたものを渡す。
// Spring が例外を投げる見出しには、errContentDisposition を包んだ誤りを返す。
//
// Java の文字列は UTF-16 の字の並びで、Go の文字列は UTF-8 のバイトの並びである。
// Spring が探す字(; " \ = ' % など)はすべて ASCII なので、Go ではバイトで探しても同じ位置で切れる。
func parseContentDisposition(header string) (contentDisposition, error) {
	parts, err := tokenizeContentDisposition(header)
	if err != nil {
		return contentDisposition{}, err
	}
	cd := contentDisposition{Type: parts[0]}
	for _, part := range parts[1:] {
		eq := strings.IndexByte(part, '=')
		if eq < 0 {
			return contentDisposition{}, fmt.Errorf("%w: 項目 %q に = が無い", errContentDisposition, part)
		}
		attribute := asciiLower(part[:eq])
		value := part[eq+1:]
		if strings.HasPrefix(value, `"`) && strings.HasSuffix(part, `"`) {
			// Java の substring(eqIndex + 2, length - 1) は、値が " の1字だけのとき、始まりが終わりを超えて例外を投げる
			if len(value) < 2 {
				return contentDisposition{}, fmt.Errorf("%w: 項目 %q の二重引用符が閉じていない", errContentDisposition, part)
			}
			value = value[1 : len(value)-1]
		}
		switch {
		case attribute == "name":
			cd.Name, cd.HasName = decodeQuotedPairsIfEscaped(value), true
		case attribute == "filename*":
			name, err := decodeExtendedFileName(value)
			if err != nil {
				return contentDisposition{}, err
			}
			cd.FileName, cd.HasFileName = name, true
		case attribute == "filename" && !cd.HasFileName:
			name, err := decodeFileName(value)
			if err != nil {
				return contentDisposition{}, err
			}
			cd.FileName, cd.HasFileName = name, true
		}
	}
	return cd, nil
}

// tokenizeContentDisposition は、Spring の tokenize にあたる。最初の ; の前を種類にし、残りを、二重引用符の外の ; で項目に分ける。
// 種類と項目は、Java の trim と同じく、前後の U+0020 以下の字(空白と制御文字)を取り除く。空の項目は捨てる。
func tokenizeContentDisposition(header string) ([]string, error) {
	index := strings.IndexByte(header, ';')
	typ := header
	if index >= 0 {
		typ = header[:index]
	}
	typ = javaTrim(typ)
	if typ == "" {
		return nil, fmt.Errorf("%w: 種類が空である", errContentDisposition)
	}
	parts := []string{typ}
	if index < 0 {
		return parts, nil
	}
	for index < len(header) {
		next := index + 1
		quoted, escaped := false, false
		for ; next < len(header); next++ {
			ch := header[next]
			if ch == ';' && !quoted {
				break
			}
			if ch == '"' && !escaped {
				quoted = !quoted
			}
			escaped = !escaped && ch == '\\'
		}
		if part := javaTrim(header[index+1 : next]); part != "" {
			parts = append(parts, part)
		}
		index = next
	}
	return parts, nil
}

// decodeExtendedFileName は、Spring の parse の filename* の分かれ道にあたる。RFC 5987 の書き方(文字コード'言語'値)を解く。
// ' が2つ無ければ、値の全体を US-ASCII として解く。Spring は、文字コードを UTF-8 と ISO-8859-1 の2つに限る。
func decodeExtendedFileName(value string) (string, error) {
	idx1 := strings.IndexByte(value, '\'')
	idx2 := -1
	if idx1 >= 0 {
		if i := strings.IndexByte(value[idx1+1:], '\''); i >= 0 {
			idx2 = idx1 + 1 + i
		}
	}
	if idx1 < 0 || idx2 < 0 {
		return decodeRFC5987(value, charsetUSASCII)
	}
	cs, err := lookupJDKCharset(javaTrim(value[:idx1]))
	if err != nil {
		return "", err
	}
	if cs != charsetUTF8 && cs != charsetISO88591 {
		return "", fmt.Errorf("%w: filename* の文字コードが UTF-8 でも ISO-8859-1 でもない", errContentDisposition)
	}
	return decodeRFC5987(value[idx2+1:], cs)
}

// decodeRFC5987 は、Spring の decodeRfc5987Filename にあたる。% と2桁の16進で書いたバイトと、RFC 5987 の attr-char を並べ、
// 文字コード cs で文字列にする。ほかの字があれば誤りにする。
// Java は、値を cs のバイト列にしてから見る。ASCII でない字は、UTF-8 でも ISO-8859-1 でも US-ASCII でも attr-char でないバイトになるので、
// Go の文字列のバイトを見ても同じ結果になる。
func decodeRFC5987(value string, cs jdkCharset) (string, error) {
	out := make([]byte, 0, len(value))
	for i := 0; i < len(value); {
		b := value[i]
		switch {
		case isRFC5987AttrChar(b):
			out = append(out, b)
			i++
		case b == '%' && i < len(value)-2:
			high, ok1 := hexDigit(value[i+1])
			low, ok2 := hexDigit(value[i+2])
			if !ok1 || !ok2 {
				return "", fmt.Errorf("%w: filename* の %% のあとが16進でない", errContentDisposition)
			}
			out = append(out, high<<4|low)
			i += 3
		default:
			return "", fmt.Errorf("%w: filename* に使えない字 %q がある", errContentDisposition, b)
		}
	}
	return cs.decode(out), nil
}

// isRFC5987AttrChar は、Spring の isRFC5987AttrChar にあたる。
func isRFC5987AttrChar(c byte) bool {
	return c >= '0' && c <= '9' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || strings.IndexByte("!#$&+-.^_`|~", c) >= 0
}

// decodeFileName は、Spring の parse の filename の分かれ道にあたる。
// 値が =? で始まれば、RFC 2047 の B の書き方を探し、無ければ Q の書き方を探す。見つかった書き方だけを解いてつなぎ、間と前後の字は捨てる。
// どちらも無ければ値をそのまま使う。=? で始まらない値は、逆スラッシュがあれば decodeQuotedPairs を通す。
func decodeFileName(value string) (string, error) {
	if !strings.HasPrefix(value, "=?") {
		return decodeQuotedPairsIfEscaped(value), nil
	}
	if matches := rfc2047Base64.FindAllStringSubmatch(value, -1); matches != nil {
		var b strings.Builder
		for _, m := range matches {
			cs, err := lookupJDKCharset(m[1])
			if err != nil {
				return "", err
			}
			decoded, err := decodeJavaBase64(m[2])
			if err != nil {
				return "", err
			}
			b.WriteString(cs.decode(decoded))
		}
		return b.String(), nil
	}
	if matches := rfc2047QuotedPrintable.FindAllStringSubmatch(value, -1); matches != nil {
		var b strings.Builder
		for _, m := range matches {
			cs, err := lookupJDKCharset(m[1])
			if err != nil {
				return "", err
			}
			decoded, err := decodeQuotedPrintable(m[2])
			if err != nil {
				return "", err
			}
			b.WriteString(cs.decode(decoded))
		}
		return b.String(), nil
	}
	return value, nil
}

// decodeQuotedPrintable は、Spring の decodeQuotedPrintableFilename のうち、文字列にする前のバイト列を作るところにあたる。
// _ を空白にし、= と2桁の16進をバイトにする。値の終わりの2字より前にない = は、そのまま残す。
// 値は正規表現が ASCII の字だけを取り出したものである。
func decodeQuotedPrintable(value string) ([]byte, error) {
	out := make([]byte, 0, len(value))
	for i := 0; i < len(value); {
		b := value[i]
		switch {
		case b == '_':
			out = append(out, ' ')
			i++
		case b == '=' && i < len(value)-2:
			high, ok1 := hexDigit(value[i+1])
			low, ok2 := hexDigit(value[i+2])
			if !ok1 || !ok2 {
				return nil, fmt.Errorf("%w: RFC 2047 の Q の = のあとが16進でない", errContentDisposition)
			}
			out = append(out, high<<4|low)
			i += 3
		default:
			out = append(out, b)
			i++
		}
	}
	return out, nil
}

// decodeQuotedPairsIfEscaped は、値に逆スラッシュがあれば、Spring の decodeQuotedPairs にあたる処理をする。
// 逆スラッシュのあとが " か \ なら逆スラッシュを取り除き、ほかの字なら逆スラッシュを残す。最後の逆スラッシュは残す。
func decodeQuotedPairsIfEscaped(value string) string {
	if strings.IndexByte(value, '\\') < 0 {
		return value
	}
	var b strings.Builder
	b.Grow(len(value))
	for i := 0; i < len(value); i++ {
		c := value[i]
		if c == '\\' && i+1 < len(value) {
			i++
			next := value[i]
			if next != '"' && next != '\\' {
				b.WriteByte(c)
			}
			b.WriteByte(next)
			continue
		}
		b.WriteByte(c)
	}
	return b.String()
}

// decodeJavaBase64 は、JDK 21 の Base64.getDecoder().decode にあたる。
// = の埋め草を省いてもよい。誤った埋め草、埋め草のあとの字、1字だけ余った最後の組は誤りにする。
// 最後の組の使わないビットが0でなくても誤りにしない。
// 写した元は、OpenJDK 21 の java.util.Base64.Decoder の decodedOutLength と decode0 である
// (https://github.com/openjdk/jdk21u/blob/master/src/java.base/share/classes/java/util/Base64.java)。
// JDK は1字だけの値を長さの計算で先に断るが、ここでは最後の組が1字しかないときの誤りになるので、同じく誤りになる。
func decodeJavaBase64(src string) ([]byte, error) {
	out := make([]byte, 0, len(src)*3/4)
	// quad は、4字の組のうち読んだ字の値で、n はその数である。JDK の shiftto の 18 12 6 0 は、n の 0 1 2 3 にあたる
	var quad [4]byte
	n := 0
	i := 0
	for i < len(src) {
		c := src[i]
		i++
		if c == '=' {
			// 2字のあとの = は、すぐあとにもう1つ = が要る。4字の組の始まりの = は余計である
			if n == 2 && (i == len(src) || src[i] != '=') || n == 0 {
				return nil, fmt.Errorf("%w: Base64 の埋め草が誤っている", errContentDisposition)
			}
			if n == 2 {
				i++
			}
			break
		}
		v, ok := base64Value(c)
		if !ok {
			return nil, fmt.Errorf("%w: Base64 に使えない字 %q がある", errContentDisposition, c)
		}
		quad[n] = v
		n++
		if n == 4 {
			out = append(out, quad[0]<<2|quad[1]>>4, quad[1]<<4|quad[2]>>2, quad[2]<<6|quad[3])
			n = 0
		}
	}
	switch n {
	case 1:
		return nil, fmt.Errorf("%w: Base64 の最後の組が1字しかない", errContentDisposition)
	case 2:
		out = append(out, quad[0]<<2|quad[1]>>4)
	case 3:
		out = append(out, quad[0]<<2|quad[1]>>4, quad[1]<<4|quad[2]>>2)
	}
	if i < len(src) {
		return nil, fmt.Errorf("%w: Base64 の埋め草のあとに字がある", errContentDisposition)
	}
	return out, nil
}

// base64Value は、Base64 の1字が表す0から63の値を返す。
func base64Value(c byte) (byte, bool) {
	switch {
	case c >= 'A' && c <= 'Z':
		return c - 'A', true
	case c >= 'a' && c <= 'z':
		return c - 'a' + 26, true
	case c >= '0' && c <= '9':
		return c - '0' + 52, true
	case c == '+':
		return 62, true
	case c == '/':
		return 63, true
	}
	return 0, false
}

// hexDigit は、Java の HexFormat.fromHexDigit にあたる。0 から 9 と、大文字と小文字の A から F を読む。
func hexDigit(c byte) (byte, bool) {
	switch {
	case c >= '0' && c <= '9':
		return c - '0', true
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10, true
	case c >= 'A' && c <= 'F':
		return c - 'A' + 10, true
	}
	return 0, false
}

// asciiLower は、ASCII の大文字だけを小文字にする。Java の toLowerCase(Locale.ROOT) は ASCII でない字も小文字にするが、
// 項目の名前 name と filename と filename* に使う字に、小文字にするとなる ASCII でない字は無い。
// Go の strings.ToLower は U+0130 を i にするので、Java と違う結果になる。そのため使わない。
func asciiLower(s string) string {
	b := []byte(s)
	for i, c := range b {
		if c >= 'A' && c <= 'Z' {
			b[i] = c + 'a' - 'A'
		}
	}
	return string(b)
}

// jdkCharset は、Go 版が JDK と同じに読める文字コードである。
type jdkCharset int

const (
	charsetUTF8 jdkCharset = iota + 1
	charsetISO88591
	charsetUSASCII
)

// jdkCharsetNames は、JDK 21 の Charset.forName が受ける、3つの文字コードの名前と別名を、ASCII の小文字にしたものである。
// JDK 21 の Charset.aliases() が返す別名を写した。JDK は、名前の ASCII の大文字と小文字を区別しない。
var jdkCharsetNames = map[string]jdkCharset{
	"utf-8": charsetUTF8, "utf8": charsetUTF8, "unicode-1-1-utf-8": charsetUTF8,
	"iso-8859-1": charsetISO88591, "819": charsetISO88591, "8859_1": charsetISO88591, "ibm-819": charsetISO88591,
	"ibm819": charsetISO88591, "iso8859-1": charsetISO88591, "iso8859_1": charsetISO88591, "iso_8859-1": charsetISO88591,
	"iso_8859-1:1987": charsetISO88591, "iso_8859_1": charsetISO88591, "cp819": charsetISO88591, "csisolatin1": charsetISO88591,
	"iso-ir-100": charsetISO88591, "l1": charsetISO88591, "latin1": charsetISO88591,
	"us-ascii": charsetUSASCII, "646": charsetUSASCII, "ansi_x3.4-1968": charsetUSASCII, "ansi_x3.4-1986": charsetUSASCII,
	"ascii": charsetUSASCII, "ibm367": charsetUSASCII, "iso646-us": charsetUSASCII, "iso_646.irv:1991": charsetUSASCII,
	"ascii7": charsetUSASCII, "cp367": charsetUSASCII, "csascii": charsetUSASCII, "iso-ir-6": charsetUSASCII,
	"iso_646.irv:1983": charsetUSASCII, "us": charsetUSASCII,
}

// lookupJDKCharset は、JDK の Charset.forName にあたる。UTF-8 と ISO-8859-1 と US-ASCII と、その別名だけを読む。
// JDK が読めないか名前が誤っている文字コードには、JDK と同じく誤りを返す。
// JDK が読めても Go 版が読まない文字コード(Shift_JIS など)にも、誤りを返す。この違いは research.md の試作の記録に書いた。
func lookupJDKCharset(name string) (jdkCharset, error) {
	if cs, ok := jdkCharsetNames[asciiLower(name)]; ok {
		return cs, nil
	}
	return 0, fmt.Errorf("%w: 文字コード %q を読まない", errContentDisposition, name)
}

// decode は、バイト列を、JDK 21 の new String(bytes, charset) と同じ規則で文字列にする。
// US-ASCII は、80 以上のバイトを1つずつ U+FFFD にする。
func (cs jdkCharset) decode(b []byte) string {
	switch cs {
	case charsetUTF8:
		return decodeJDKUTF8(b)
	case charsetISO88591:
		r := make([]rune, len(b))
		for i, c := range b {
			r[i] = rune(c)
		}
		return string(r)
	default:
		var s strings.Builder
		s.Grow(len(b))
		for _, c := range b {
			if c < utf8.RuneSelf {
				s.WriteByte(c)
			} else {
				s.WriteRune(utf8.RuneError)
			}
		}
		return s.String()
	}
}
