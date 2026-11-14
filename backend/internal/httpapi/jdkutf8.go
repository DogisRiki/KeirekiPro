package httpapi

import (
	"strings"
	"unicode/utf8"
)

// decodeJDKUTF8 は、バイトの並びを、Java 版の JDK 21 の new String(bytes, StandardCharsets.UTF_8) と同じ規則で文字列にする。
// Java 版は、multipart の文字の部分の中身をこの規則で文字列にする。
//
// 写した元は、OpenJDK 21 の java.lang.String の decodeUTF8_UTF16 と、それが呼ぶ isMalformed3 などの関数である
// (https://github.com/openjdk/jdk21u/blob/master/src/java.base/share/classes/java/lang/String.java)。
// UTF-8 として誤ったバイトを U+FFFD に置き換える数と、置き換えたあとに読み進める位置が、Go の標準の置き換えと違う。
// research.md の試作の記録の P8 に、違いの例を書いた。
//
// Java の byte は符号付きなので、JDK のソースは負の値で先頭のバイトを見分ける。ここでは符号の無い値で、同じ範囲を見分ける。
func decodeJDKUTF8(src []byte) string {
	var b strings.Builder
	b.Grow(len(src))
	sl := len(src)
	sp := 0
	for sp < sl {
		b1 := src[sp]
		sp++
		switch {
		case b1 < 0x80:
			b.WriteByte(b1)
		case b1 >= 0xC2 && b1 <= 0xDF:
			// 2バイトの字。C0 と C1 は冗長な形なので、最後の default に回る
			if sp < sl {
				b2 := src[sp]
				sp++
				if isNotContinuation(b2) {
					b.WriteRune(utf8.RuneError)
					sp--
				} else {
					b.WriteRune(rune(b1&0x1F)<<6 | rune(b2&0x3F))
				}
				continue
			}
			b.WriteRune(utf8.RuneError)
			return b.String()
		case b1&0xF0 == 0xE0:
			// 3バイトの字
			if sp+1 < sl {
				b2, b3 := src[sp], src[sp+1]
				sp += 2
				if isMalformed3(b1, b2, b3) {
					b.WriteRune(utf8.RuneError)
					sp -= 3
					sp += malformed3(src, sp)
					continue
				}
				// JDK は、サロゲートの範囲(D800 から DFFF)の字を、3バイトをまとめて1つの U+FFFD にする。
				// Go の WriteRune も、サロゲートの範囲の字を U+FFFD にして書くので、同じ結果になる
				b.WriteRune(rune(b1&0x0F)<<12 | rune(b2&0x3F)<<6 | rune(b3&0x3F))
				continue
			}
			if sp < sl && isMalformed3_2(b1, src[sp]) {
				b.WriteRune(utf8.RuneError)
				continue
			}
			// 末尾で切れた字は、残りのバイトをまとめて1つの U+FFFD にして終える
			b.WriteRune(utf8.RuneError)
			return b.String()
		case b1&0xF8 == 0xF0:
			// 4バイトの字
			if sp+2 < sl {
				b2, b3, b4 := src[sp], src[sp+1], src[sp+2]
				sp += 3
				var uc rune
				if !isMalformed4(b2, b3, b4) {
					uc = rune(b1&0x07)<<18 | rune(b2&0x3F)<<12 | rune(b3&0x3F)<<6 | rune(b4&0x3F)
				}
				// uc が 0x10000 から 0x10FFFF の外なら、冗長な形か、Unicode の外の字である
				if isMalformed4(b2, b3, b4) || uc < 0x10000 || uc > utf8.MaxRune {
					b.WriteRune(utf8.RuneError)
					sp -= 4
					sp += malformed4(src, sp)
				} else {
					b.WriteRune(uc)
				}
				continue
			}
			if b1 > 0xF4 || sp < sl && isMalformed4_2(b1, src[sp]) {
				b.WriteRune(utf8.RuneError)
				continue
			}
			sp++
			b.WriteRune(utf8.RuneError)
			if sp < sl && isNotContinuation(src[sp]) {
				continue
			}
			return b.String()
		default:
			// 続きのバイト(80 から BF)、2バイトの冗長な形の先頭(C0 と C1)、使わない先頭のバイト(F8 から FF)
			b.WriteRune(utf8.RuneError)
		}
	}
	return b.String()
}

// isNotContinuation は、JDK の isNotContinuation と isMalformed4_3 にあたる。続きのバイト(80 から BF)でなければ真である。
func isNotContinuation(c byte) bool {
	return c&0xC0 != 0x80
}

// isMalformed3 は、JDK の isMalformed3 にあたる。E0 のあとの 80 から 9F は、冗長な形である。
func isMalformed3(b1, b2, b3 byte) bool {
	return (b1 == 0xE0 && b2&0xE0 == 0x80) || isNotContinuation(b2) || isNotContinuation(b3)
}

// isMalformed3_2 は、JDK の isMalformed3_2 にあたる。
func isMalformed3_2(b1, b2 byte) bool {
	return (b1 == 0xE0 && b2&0xE0 == 0x80) || isNotContinuation(b2)
}

// isMalformed4 は、JDK の isMalformed4 にあたる。
func isMalformed4(b2, b3, b4 byte) bool {
	return isNotContinuation(b2) || isNotContinuation(b3) || isNotContinuation(b4)
}

// isMalformed4_2 は、JDK の isMalformed4_2 にあたる。F0 のあとは 90 から BF、F4 のあとは 80 から 8F だけを許す。
func isMalformed4_2(b1, b2 byte) bool {
	return (b1 == 0xF0 && (b2 < 0x90 || b2 > 0xBF)) || (b1 == 0xF4 && b2&0xF0 != 0x80) || isNotContinuation(b2)
}

// malformed3 は、JDK の malformed3 にあたる。誤った3バイトの字の先頭 src[sp] から、1つの U+FFFD にまとめるバイトの数を返す。
func malformed3(src []byte, sp int) int {
	if isMalformed3_2(src[sp], src[sp+1]) {
		return 1
	}
	return 2
}

// malformed4 は、JDK の malformed4 にあたる。誤った4バイトの字の先頭 src[sp] から、1つの U+FFFD にまとめるバイトの数を返す。
func malformed4(src []byte, sp int) int {
	b1, b2 := src[sp], src[sp+1]
	if b1 > 0xF4 || isMalformed4_2(b1, b2) {
		return 1
	}
	if isNotContinuation(src[sp+2]) {
		return 2
	}
	return 3
}
