package httpapi

import (
	"strings"
	"unicode"
	"unicode/utf8"

	"golang.org/x/text/unicode/norm"
	"golang.org/x/text/unicode/rangetable"
)

// formatContentDisposition は、出力の答えの Content-Disposition のヘッダを作る。Java 版は、Spring 7.0.10 の
// ContentDisposition に、ファイル名と UTF-8 を渡してヘッダを作る。この関数は、その toString と同じ字を作る。
// inline が真なら種類を inline に、偽なら attachment にする。
//
// 写した元は、Spring 7.0.10 の ContentDisposition の toString、appendName、transliterateToAscii、encodeRfc5987Filename である
// (https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-web/src/main/java/org/springframework/http/ContentDisposition.java)。
//
// fileName は、resume パッケージの sanitizeFileName が作った名前に拡張子を付けたものである。sanitizeFileName は、UTF-16 の255で
// 切って半分に割れた絵文字の前の半分を、Java の文字列と同じくサロゲートのまま、UTF-8 と同じ規則の3バイトで返す。
// この関数は、その3バイトを、Java 版と同じく、filename="…" では _ 1つに、filename*= では ? に書く。
func formatContentDisposition(inline bool, fileName string) string {
	kind := "attachment"
	if inline {
		kind = "inline"
	}
	return kind + `; filename="` + transliterateToASCII(quoteDispositionName(fileName)) + `"; filename*=` + encodeRFC5987(fileName)
}

// quoteDispositionName は、Spring の appendName を写した。制御の字を落とし、" と \ の前に \ を置く。
// 落とす字と \ を置く字はどれも ASCII なので、バイトごとに見ても、UTF-8 の字の途中のバイトに当たらない。
func quoteDispositionName(name string) string {
	var b strings.Builder
	for i := 0; i < len(name); i++ {
		c := name[i]
		if c <= 0x1f || c == 0x7f {
			continue
		}
		if c == '"' || c == '\\' {
			b.WriteByte('\\')
		}
		b.WriteByte(c)
	}
	return b.String()
}

// asciiTransliterations は、Spring の transliterateToAscii が決まった ASCII の字に写す字の表である。
var asciiTransliterations = map[rune]string{
	'ä': "ae", 'ö': "oe", 'ü': "ue",
	'Ä': "Ae", 'Ö': "Oe", 'Ü': "Ue",
	'ß': "ss",
	'æ': "ae", 'Æ': "AE",
	'œ': "oe", 'Œ': "OE",
}

// jdkAssigned は、Java 版を動かす JDK 21 の Unicode の版(15.0)で割り当てられた字の表である。
var jdkAssigned = rangetable.Assigned("15.0.0")

// transliterateToASCII は、Spring の transliterateToAscii を写した。ASCII の字はそのまま書き、表にある字は表のとおりに写す。
// ほかの字は正準分解で分け、分けた字のうち ASCII の字を書き、結合の記号(Mn、Mc、Me)を落とし、ほかの字を _ にする。
//
// Java 版を動かす JDK 21 は Unicode 15.0 の表を使い、Go の unicode と norm は、それより新しい版の表を使う。
// Unicode 15.0 で割り当てられていない字は、JDK 21 では分けられず、種類が UNASSIGNED になって _ になるので、ここでも _ にする。
func transliterateToASCII(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); {
		if isSurrogateBytes(s, i) {
			// Java の codePointAt は、対にならないサロゲートを、そのまま1つの字として返す。サロゲートは結合の記号ではない
			b.WriteByte('_')
			i += 3
			continue
		}
		r, size := utf8.DecodeRuneInString(s[i:])
		i += size
		if r <= unicode.MaxASCII {
			b.WriteRune(r)
			continue
		}
		if t, ok := asciiTransliterations[r]; ok {
			b.WriteString(t)
			continue
		}
		if !unicode.Is(jdkAssigned, r) {
			b.WriteByte('_')
			continue
		}
		for _, nr := range norm.NFD.String(string(r)) {
			switch {
			case nr <= unicode.MaxASCII:
				b.WriteRune(nr)
			case !unicode.In(nr, unicode.Mn, unicode.Mc, unicode.Me):
				b.WriteByte('_')
			}
		}
	}
	return b.String()
}

// encodeRFC5987 は、Spring の encodeRfc5987Filename を、UTF-8 のときについて写した。ファイル名を Java と同じく UTF-8 の
// バイトにし、英数字と !#$&+-.^_`|~ をそのまま書き、ほかのバイトを大文字の %XX に書く。
func encodeRFC5987(s string) string {
	const hex = "0123456789ABCDEF"
	var b strings.Builder
	b.WriteString("UTF-8''")
	for i := 0; i < len(s); i++ {
		c := s[i]
		if isSurrogateBytes(s, i) {
			// Java の String.getBytes(UTF_8) は、対にならないサロゲートを ? にする
			c = '?'
			i += 2
		}
		if isRFC5987AttrChar(c) {
			b.WriteByte(c)
			continue
		}
		b.WriteByte('%')
		b.WriteByte(hex[c>>4])
		b.WriteByte(hex[c&0x0f])
	}
	return b.String()
}

// isSurrogateBytes は、s の i バイト目から、サロゲート(U+D800 から U+DFFF)を UTF-8 と同じ規則で書いた3バイトが始まるかを返す。
func isSurrogateBytes(s string, i int) bool {
	return i+2 < len(s) && s[i] == 0xED && s[i+1] >= 0xA0 && s[i+1] <= 0xBF
}
