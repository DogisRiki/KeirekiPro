package auth

import (
	"sort"
	"strings"
)

// このファイルは、Java 版のメールアドレスの検査(Hibernate Validator の EmailValidator)が呼ぶ、
// JDK 21 の java.net.IDN.toASCII(domain) を写す。表は nameprep_table.go にある。
// 呼ぶ側が、ドメインの部分が基本多言語面(U+0000 から U+FFFF)の文字だけでできていることを先に確かめる。
// Java 版の正規表現は、それより先の文字を受け付けないためである。

// ドメインの部分の区切りの文字。java.net.IDN は、この4つの文字の位置でラベルを分ける。
const (
	idnaFullStop          = '.'
	idnaIdeographicStop   = '。'
	idnaFullwidthStop     = '．'
	idnaHalfwidthIdeoStop = '｡'
)

// idnaMaxLabelLength は、変換したあとのラベルの長さの上限である(java.net.IDN の MAX_LABEL_LENGTH)。
const idnaMaxLabelLength = 63

// isIDNADot は、r が java.net.IDN のラベルの区切りの文字かを返す。
func isIDNADot(r rune) bool {
	return r == idnaFullStop || r == idnaIdeographicStop || r == idnaFullwidthStop || r == idnaHalfwidthIdeoStop
}

// idnaToASCII は、java.net.IDN.toASCII(s) と同じく、ドメインの部分を ASCII の形に変える。
// java.net.IDN が IllegalArgumentException を投げる入力では、false を返す。
func idnaToASCII(s string) (string, bool) {
	runes := []rune(s)
	if len(runes) == 1 && isIDNADot(runes[0]) {
		return ".", true
	}
	var b strings.Builder
	for p := 0; p < len(runes); {
		q := p
		for q < len(runes) && !isIDNADot(runes[q]) {
			q++
		}
		label, ok := idnaLabelToASCII(runes[p:q])
		if !ok {
			return "", false
		}
		b.WriteString(label)
		if q != len(runes) {
			b.WriteByte('.')
		}
		p = q + 1
	}
	return b.String(), true
}

// idnaLabelToASCII は、java.net.IDN の toASCIIInternal と同じく、1つのラベルを変える。
// ASCII だけのラベルはそのまま使う。ASCII の外の文字を含むラベルは、nameprep を通し、結果が ASCII だけでなければ、
// 「xn--」で始まる Punycode の形にする。
func idnaLabelToASCII(label []rune) (string, bool) {
	dest := label
	if !isAllASCII(label) {
		prepared, ok := nameprep(label)
		if !ok {
			return "", false
		}
		dest = prepared
	}
	if len(dest) == 0 {
		return "", false
	}
	out := string(dest)
	if !isAllASCII(dest) {
		if len(out) >= 4 && strings.EqualFold(out[:4], "xn--") {
			return "", false
		}
		// java.net.IDN は Punycode の結果を小文字にするが、ここに来るラベルは nameprep の対応づけ(B.2)で英大文字が
		// 小文字になっているので、小文字にする手順は要らない。
		out = "xn--" + punycodeEncode(dest)
	}
	if len(out) > idnaMaxLabelLength {
		return "", false
	}
	return out, true
}

// isAllASCII は、rs がすべて ASCII の文字かを返す。
func isAllASCII(rs []rune) bool {
	for _, r := range rs {
		if r >= 0x80 {
			return false
		}
	}
	return true
}

// nameprep は、java.net.IDN が使う nameprep(RFC 3491)の準備を、ALLOW_UNASSIGNED を付けずに行う。
// 割り当ての無い文字があれば断り、対応づけと互換の正規化(NFKC)のあとに、禁じる文字と、書く向きの決まりを確かめる。
func nameprep(label []rune) ([]rune, bool) {
	var decomposed []rune
	for _, r := range label {
		if inRanges(nameprepUnassigned, r) {
			return nil, false
		}
		if d, ok := nameprepDecomposition[r]; ok {
			decomposed = append(decomposed, []rune(d)...)
		} else {
			decomposed = append(decomposed, r)
		}
	}
	out := compose(reorder(decomposed))
	var hasRandAL, hasL bool
	for _, r := range out {
		if inRanges(nameprepProhibited, r) {
			return nil, false
		}
		hasRandAL = hasRandAL || inRanges(nameprepRandAL, r)
		hasL = hasL || inRanges(nameprepL, r)
	}
	if hasRandAL && (hasL || !inRanges(nameprepRandAL, out[0]) || !inRanges(nameprepRandAL, out[len(out)-1])) {
		return nil, false
	}
	return out, true
}

// inRanges は、r が、下端と上端の組の並び table のどれかの範囲にあるかを返す。
func inRanges(table []uint16, r rune) bool {
	n := len(table) / 2
	i := sort.Search(n, func(i int) bool { return rune(table[2*i+1]) >= r })
	return i < n && rune(table[2*i]) <= r
}

// combiningClass は、r の正準の結合の種類を返す。
func combiningClass(r rune) int {
	n := len(nameprepCombiningClass) / 3
	i := sort.Search(n, func(i int) bool { return rune(nameprepCombiningClass[3*i+1]) >= r })
	if i < n && rune(nameprepCombiningClass[3*i]) <= r {
		return int(nameprepCombiningClass[3*i+2])
	}
	return 0
}

// reorder は、結合の種類が0でない文字の続きを、結合の種類の小さい順に、同じ種類の中の順を変えずに並べ直す(正準の並べ替え)。
func reorder(rs []rune) []rune {
	for i := 1; i < len(rs); i++ {
		for j := i; j > 0; j-- {
			c, prev := combiningClass(rs[j]), combiningClass(rs[j-1])
			if c == 0 || prev <= c {
				break
			}
			rs[j], rs[j-1] = rs[j-1], rs[j]
		}
	}
	return rs
}

// ハングルの音節の合成に使う値(Unicode の規格の 3.12 節)。
const (
	hangulSBase  = 0xAC00
	hangulLBase  = 0x1100
	hangulVBase  = 0x1161
	hangulTBase  = 0x11A7
	hangulLCount = 19
	hangulVCount = 21
	hangulTCount = 28
	hangulNCount = hangulVCount * hangulTCount
	hangulSCount = hangulLCount * hangulNCount
)

// composePair は、正準の合成で、a と b を合成した文字を返す。
func composePair(a, b rune) (rune, bool) {
	if a >= hangulLBase && a < hangulLBase+hangulLCount && b >= hangulVBase && b < hangulVBase+hangulVCount {
		return hangulSBase + ((a-hangulLBase)*hangulVCount+(b-hangulVBase))*hangulTCount, true
	}
	if a >= hangulSBase && a < hangulSBase+hangulSCount && (a-hangulSBase)%hangulTCount == 0 &&
		b > hangulTBase && b < hangulTBase+hangulTCount {
		return a + (b - hangulTBase), true
	}
	c, ok := nameprepComposition[[2]rune{a, b}]
	return c, ok
}

// compose は、並べ直した分解の結果を、正準の合成で組み立てる(Unicode の正規化の UAX #15 の合成の手順)。
// 文字は、合成の相手の文字との間に、結合の種類が0の文字か、自分以上の種類の文字があると、合成されない。
func compose(rs []rune) []rune {
	out := make([]rune, 0, len(rs))
	starter := -1
	lastClass := 0
	for _, r := range rs {
		c := combiningClass(r)
		if starter >= 0 && (len(out)-1 == starter || (lastClass != 0 && lastClass < c)) {
			if composed, ok := composePair(out[starter], r); ok {
				out[starter] = composed
				continue
			}
		}
		if c == 0 {
			starter = len(out)
		}
		lastClass = c
		out = append(out, r)
	}
	return out
}

// Punycode(RFC 3492)の値。
const (
	punyBase        = 36
	punyTMin        = 1
	punyTMax        = 26
	punySkew        = 38
	punyDamp        = 700
	punyInitialBias = 72
	punyInitialN    = 128
)

// punycodeEncode は、RFC 3492 の Punycode で rs を符号にする。基本の文字(ASCII)は大文字と小文字を変えずに写す。
func punycodeEncode(rs []rune) string {
	var b strings.Builder
	for _, r := range rs {
		if r < 0x80 {
			b.WriteRune(r)
		}
	}
	basic := b.Len()
	handled := basic
	if basic > 0 {
		b.WriteByte('-')
	}
	n, delta, bias := rune(punyInitialN), 0, punyInitialBias
	for handled < len(rs) {
		m := rune(0x7FFFFFFF)
		for _, r := range rs {
			if r >= n && r < m {
				m = r
			}
		}
		delta += int(m-n) * (handled + 1)
		n = m
		for _, r := range rs {
			if r < n {
				delta++
			}
			if r != n {
				continue
			}
			q := delta
			for k := punyBase; ; k += punyBase {
				t := k - bias
				if t < punyTMin {
					t = punyTMin
				} else if t > punyTMax {
					t = punyTMax
				}
				if q < t {
					break
				}
				b.WriteByte(punyDigit(t + (q-t)%(punyBase-t)))
				q = (q - t) / (punyBase - t)
			}
			b.WriteByte(punyDigit(q))
			bias = punyAdapt(delta, handled+1, handled == basic)
			delta = 0
			handled++
		}
		delta++
		n++
	}
	return b.String()
}

// punyDigits は、Punycode の数字 0 から 35 の文字である。
const punyDigits = "abcdefghijklmnopqrstuvwxyz0123456789"

// punyDigit は、Punycode の数字 d(0 から 35)の文字を返す。
func punyDigit(d int) byte {
	return punyDigits[d]
}

// punyAdapt は、RFC 3492 の 6.1 節の bias の調整を行う。
func punyAdapt(delta, numPoints int, first bool) int {
	if first {
		delta /= punyDamp
	} else {
		delta /= 2
	}
	delta += delta / numPoints
	k := 0
	for delta > ((punyBase-punyTMin)*punyTMax)/2 {
		delta /= punyBase - punyTMin
		k += punyBase
	}
	return k + (punyBase-punyTMin+1)*delta/(delta+punySkew)
}
