package resume

import (
	"bytes"
	"unicode/utf16"
	"unicode/utf8"
)

// jvKind は、JSON の値の木の値の種類である。
type jvKind uint8

const (
	jvNull jvKind = iota
	jvBool
	jvNumber
	jvString
	jvArray
	jvObject
)

// jv は、parseJTree が作る JSON の値の木の1つの値である。
type jv struct {
	kind jvKind
	// text は、文字列の値か、JSON に書かれた字のままの数である。文字列の対になっていないサロゲートは、WTF-8 のバイトで持つ。
	text string
	// truth は、真偽の値である。
	truth bool
	// items は、並びの要素である。
	items []*jv
	// members は、オブジェクトの欄を、本文に書かれた順に並べたものである。同じ名前の欄が2つあれば、両方を持つ。
	// Java 版の Jackson は、同じ名前の欄の値をすべて読み、あとの値を使う。前の値を読めなければ、本文を読めない。
	members []jvMember
}

// jvMember は、オブジェクトの1つの欄の名前と値である。
type jvMember struct {
	name  string
	value *jv
}

// jtreeMaxDepth は、Java 版の Jackson 3(jackson-core 3.1.7)の既定の、オブジェクトと並びの入れ子の深さの上限である
// (StreamReadConstraints.DEFAULT_MAX_DEPTH。Java 版の spring.jackson.use-jackson2-defaults は、この上限を変えない)。
// Jackson は、一番外の値の深さを 1 と数え、深さが上限を超える値を読めない。
const jtreeMaxDepth = 500

// jtreeMaxNameLen は、Java 版の Jackson の既定の、欄の名前の長さの上限である(StreamReadConstraints.DEFAULT_MAX_NAME_LEN)。
// Jackson は、番号で書いた字を UTF-8 に直したバイト数と、ほかの字の書かれたままのバイト数を足して名前の長さとし、
// 長さが上限を超える名前を読めない(jackson-core 3.1.7 の UTF8StreamJsonParser の addName)。
const jtreeMaxNameLen = 50000

// utf8BOM は、UTF-8 の BOM である。Java 版の Jackson は、本文の頭の BOM を読み飛ばす。
var utf8BOM = []byte{0xEF, 0xBB, 0xBF}

// parseJTree は、本文 in の最初の JSON の値を、Java 版の Jackson と同じ規則で読み、値の木を返す。
// 読めなければ false を返す。最初の値のあとに続く字は読まない。Java 版の Jackson も、最初の値だけを読むためである。
// 一番外の値がオブジェクトでも並びでもないときに、Jackson は、値のすぐあとの字も確かめるが、parseJTree は確かめない。
// 戻しの本文の読み手は、一番外がオブジェクトでない本文を読めない本文とするので、この違いは答えを変えない。
//
// Jackson と同じく、parseJTree は、JSON の規則にない書き方(引用符が ' の文字列、名前を引用符で囲まない欄、
// 最後の , 、先頭の 0 を続けた数、+ で始まる数、NaN、注釈)を読めない。空白は、空白、タブ、改行、復帰の4つだけである。
// 文字列は、Java の文字列と同じ UTF-16 の単位の並びとして読み、木には WTF-8 で持つ。そのため、
// \uD800 から \uDFFF の番号で書かれた対になっていないサロゲートは、WTF-8 のバイトとして残る。
func parseJTree(in []byte) (*jv, bool) {
	p := &jtreeParser{in: bytes.TrimPrefix(in, utf8BOM)}
	p.skipSpace()
	return p.value(0)
}

// jtreeParser は、parseJTree の読みかけの状態である。
type jtreeParser struct {
	in  []byte
	pos int
}

// skipSpace は、JSON の空白を読み飛ばす。
func (p *jtreeParser) skipSpace() {
	for p.pos < len(p.in) {
		switch p.in[p.pos] {
		case ' ', '\t', '\n', '\r':
			p.pos++
		default:
			return
		}
	}
}

// value は、p.pos から1つの値を読む。depth は、値を囲むオブジェクトと並びの数である。
func (p *jtreeParser) value(depth int) (*jv, bool) {
	if p.pos >= len(p.in) {
		return nil, false
	}
	switch c := p.in[p.pos]; {
	case c == '{':
		return p.object(depth + 1)
	case c == '[':
		return p.array(depth + 1)
	case c == '"':
		s, ok := p.str(false)
		if !ok {
			return nil, false
		}
		return &jv{kind: jvString, text: s}, true
	case c == '-' || isASCIIDigit(c):
		return p.number()
	case c == 't':
		return p.literal("true", &jv{kind: jvBool, truth: true})
	case c == 'f':
		return p.literal("false", &jv{kind: jvBool})
	case c == 'n':
		return p.literal("null", &jv{kind: jvNull})
	default:
		return nil, false
	}
}

// object は、p.pos の { から、オブジェクトを読む。depth は、このオブジェクトの深さである。
func (p *jtreeParser) object(depth int) (*jv, bool) {
	if depth > jtreeMaxDepth {
		return nil, false
	}
	p.pos++
	v := &jv{kind: jvObject}
	p.skipSpace()
	if p.pos < len(p.in) && p.in[p.pos] == '}' {
		p.pos++
		return v, true
	}
	for {
		if p.pos >= len(p.in) || p.in[p.pos] != '"' {
			return nil, false
		}
		name, ok := p.str(true)
		if !ok {
			return nil, false
		}
		p.skipSpace()
		if p.pos >= len(p.in) || p.in[p.pos] != ':' {
			return nil, false
		}
		p.pos++
		p.skipSpace()
		item, ok := p.value(depth)
		if !ok {
			return nil, false
		}
		v.members = append(v.members, jvMember{name: name, value: item})
		if more, ok := p.next('}'); !ok || !more {
			return closed(v, ok)
		}
	}
}

// array は、p.pos の [ から、並びを読む。depth は、この並びの深さである。
func (p *jtreeParser) array(depth int) (*jv, bool) {
	if depth > jtreeMaxDepth {
		return nil, false
	}
	p.pos++
	v := &jv{kind: jvArray, items: []*jv{}}
	p.skipSpace()
	if p.pos < len(p.in) && p.in[p.pos] == ']' {
		p.pos++
		return v, true
	}
	for {
		item, ok := p.value(depth)
		if !ok {
			return nil, false
		}
		v.items = append(v.items, item)
		if more, ok := p.next(']'); !ok || !more {
			return closed(v, ok)
		}
	}
}

// next は、値のあとの空白と区切りを読む。区切りが , なら、その後ろの空白まで読んで、次の値があること(more が true)を返す。
// 区切りが end なら、end まで読んで、次の値が無いことを返す。どちらでもなければ、ok に false を返す。
func (p *jtreeParser) next(end byte) (more, ok bool) {
	p.skipSpace()
	if p.pos >= len(p.in) {
		return false, false
	}
	switch p.in[p.pos] {
	case ',':
		p.pos++
		p.skipSpace()
		return true, true
	case end:
		p.pos++
		return false, true
	default:
		return false, false
	}
}

// closed は、next の答えから、オブジェクトか並びの v を読み終えたときの値を返す。
func closed(v *jv, ok bool) (*jv, bool) {
	if !ok {
		return nil, false
	}
	return v, true
}

// literal は、p.pos から字 word を読み、v を返す。
func (p *jtreeParser) literal(word string, v *jv) (*jv, bool) {
	if !bytes.HasPrefix(p.in[p.pos:], []byte(word)) {
		return nil, false
	}
	p.pos += len(word)
	return v, true
}

// number は、p.pos から、JSON の規則の数を読み、JSON に書かれた字のままの数を返す。
func (p *jtreeParser) number() (*jv, bool) {
	start := p.pos
	if p.in[p.pos] == '-' {
		p.pos++
	}
	switch {
	case p.pos < len(p.in) && p.in[p.pos] == '0':
		p.pos++
		// Jackson は、先頭の 0 のあとに数字を続けた数を読めない
		if p.pos < len(p.in) && isASCIIDigit(p.in[p.pos]) {
			return nil, false
		}
	case !p.digits():
		return nil, false
	}
	if p.pos < len(p.in) && p.in[p.pos] == '.' {
		p.pos++
		if !p.digits() {
			return nil, false
		}
	}
	if p.pos < len(p.in) && (p.in[p.pos] == 'e' || p.in[p.pos] == 'E') {
		p.pos++
		if p.pos < len(p.in) && (p.in[p.pos] == '+' || p.in[p.pos] == '-') {
			p.pos++
		}
		if !p.digits() {
			return nil, false
		}
	}
	return &jv{kind: jvNumber, text: string(p.in[start:p.pos])}, true
}

// digits は、p.pos から続く数字を読み、1つ以上読めたかを返す。
func (p *jtreeParser) digits() bool {
	start := p.pos
	for p.pos < len(p.in) && isASCIIDigit(p.in[p.pos]) {
		p.pos++
	}
	return p.pos > start
}

// str は、p.pos の " から、文字列を読み、WTF-8 の字を返す。name が true なら、欄の名前として読み、
// 番号で書いたサロゲートが対になっていることと、名前の長さが jtreeMaxNameLen を超えないことも確かめる。
func (p *jtreeParser) str(name bool) (string, bool) {
	p.pos++
	var units []uint16
	size := 0 // Jackson が数える、名前の長さ
	for p.pos < len(p.in) {
		c := p.in[p.pos]
		start := p.pos
		switch {
		case c == '"':
			p.pos++
			if name && size > jtreeMaxNameLen {
				return "", false
			}
			return wtf8FromUnits(units), true
		case c == '\\':
			n := len(units)
			var ok bool
			if units, ok = p.escapeTo(units, name); !ok {
				return "", false
			}
			size += escapedLen(units[n:])
			continue
		case c < 0x20:
			// Jackson は、番号にせずに書いた 0x20 より小さい字を読めない
			return "", false
		case c < utf8.RuneSelf:
			units = append(units, uint16(c))
			p.pos++
		default:
			var ok bool
			if units, ok = p.utf8Char(units); !ok {
				return "", false
			}
		}
		size += p.pos - start
	}
	return "", false
}

// escapeTo は、p.pos の \ から、番号の書き方を読み、UTF-16 の単位を units に足す。name が true なら、Java 版の Jackson
// (jackson-core 3.1.7 の UTF8StreamJsonParser の parseEscapedName と、JsonParserBase の _decodeSurrogate と
// _reportUnexpectedLowSurrogate)と同じく、欄の名前の番号の前の半分のサロゲートのすぐあとに、後ろの半分のサロゲートの
// 番号が続くことを求め、番号で書いた後ろの半分のサロゲートだけの字を読めない。文字列の値では、対になっていないサロゲートも読む。
func (p *jtreeParser) escapeTo(units []uint16, name bool) ([]uint16, bool) {
	u, ok := p.escape()
	if !ok {
		return units, false
	}
	if !name || !utf16.IsSurrogate(rune(u)) {
		return append(units, u), true
	}
	if u >= 0xDC00 || p.pos >= len(p.in) || p.in[p.pos] != '\\' {
		return units, false
	}
	lo, ok := p.escape()
	if !ok || lo < 0xDC00 || lo > 0xDFFF {
		return units, false
	}
	return append(units, u, lo), true
}

// escapedLen は、escapeTo が足した UTF-16 の単位 units を、Jackson が欄の名前の長さとして数える UTF-8 のバイト数にする。
func escapedLen(units []uint16) int {
	if len(units) == 2 {
		return 4
	}
	return utf8.RuneLen(rune(units[0]))
}

// escape は、p.pos の \ から、文字列の中の番号の書き方を1つ読み、UTF-16 の単位を返す。
func (p *jtreeParser) escape() (uint16, bool) {
	p.pos++
	if p.pos >= len(p.in) {
		return 0, false
	}
	c := p.in[p.pos]
	p.pos++
	switch c {
	case '"', '\\', '/':
		return uint16(c), true
	case 'b':
		return '\b', true
	case 'f':
		return '\f', true
	case 'n':
		return '\n', true
	case 'r':
		return '\r', true
	case 't':
		return '\t', true
	case 'u':
		if p.pos+4 > len(p.in) {
			return 0, false
		}
		var u uint16
		for _, h := range p.in[p.pos : p.pos+4] {
			d, ok := hexDigit(h)
			if !ok {
				return 0, false
			}
			u = u<<4 | d
		}
		p.pos += 4
		return u, true
	default:
		return 0, false
	}
}

// hexDigit は、16進数の字 c の値を返す。
func hexDigit(c byte) (uint16, bool) {
	switch {
	case c >= '0' && c <= '9':
		return uint16(c - '0'), true
	case c >= 'a' && c <= 'f':
		return uint16(c-'a') + 10, true
	case c >= 'A' && c <= 'F':
		return uint16(c-'A') + 10, true
	default:
		return 0, false
	}
}

// utf8Char は、p.pos から、0x80 以上のバイトで始まる1字を、Java 版の Jackson と同じ規則で読み、
// UTF-16 の単位を units に足す。Jackson は、続きのバイトが 0x80 から 0xBF にあることと、3バイトの字がサロゲートでないことを
// 確かめる。Jackson は、短く書けるのに長く書いた字(0xC0 0x80 のような字)と、U+10FFFF を超える4バイトの字を読めない字とせず、
// 次の計算で UTF-16 の単位にする(jackson-core 3.1.7)。parseJTree も、Java 版と同じ字にするため、同じ計算をする。
// ただし、Jackson は、欄の名前では前の半分を | でなく足し算で作る(UTF8StreamJsonParser の addName)。2つが違う字になるのは、
// 欄の名前に長く書いた4バイトの字(0xF0 0x80 から 0xF0 0x8F で始まる字)があるときだけである。その名前は、戻しの本文の型のどの欄の
// 名前にも当たらず、名前どうしが同じかどうかも Java 版と変わらないため、parseJTree は、欄の名前でも | で作る。
func (p *jtreeParser) utf8Char(units []uint16) ([]uint16, bool) {
	c := int32(p.in[p.pos])
	var size int
	switch {
	case c&0xE0 == 0xC0:
		size, c = 2, c&0x1F
	case c&0xF0 == 0xE0:
		size, c = 3, c&0x0F
	case c&0xF8 == 0xF0:
		size, c = 4, c&0x07
	default:
		return units, false
	}
	if p.pos+size > len(p.in) {
		return units, false
	}
	for _, d := range p.in[p.pos+1 : p.pos+size] {
		if d&0xC0 != 0x80 {
			return units, false
		}
		c = c<<6 | int32(d&0x3F)
	}
	p.pos += size
	switch size {
	case 3:
		if c >= 0xD800 && c <= 0xDFFF {
			return units, false
		}
	case 4:
		// Jackson の UTF8StreamJsonParser の _decodeUtf8_4 と、その呼び手の計算である。0x10000 を引いた値を、
		// 足し算でなく | で 0xD800 と 0xDC00 に重ねる。
		c -= 0x10000
		return append(units, 0xD800|uint16(c>>10&0xFFFF), 0xDC00|uint16(c&0x3FF)), true
	}
	return append(units, uint16(c)), true
}

// wtf8FromUnits は、UTF-16 の単位の並び units を、WTF-8 の字にする。前の半分のサロゲートのすぐあとに後ろの半分の
// サロゲートが続けば、その組を1つの字にする。ほかのサロゲートは、対になっていないサロゲートとして、UTF-8 と同じ規則の
// 3バイトにする。
func wtf8FromUnits(units []uint16) string {
	b := make([]byte, 0, len(units))
	for i := 0; i < len(units); i++ {
		u := rune(units[i])
		switch {
		case utf16.IsSurrogate(u) && u < 0xDC00 && i+1 < len(units) && units[i+1] >= 0xDC00 && units[i+1] <= 0xDFFF:
			b = utf8.AppendRune(b, utf16.DecodeRune(u, rune(units[i+1])))
			i++
		case utf16.IsSurrogate(u):
			b = append(b, 0xE0|byte(u>>12&0x0F), 0x80|byte(u>>6&0x3F), 0x80|byte(u&0x3F))
		default:
			b = utf8.AppendRune(b, u)
		}
	}
	return string(b)
}
