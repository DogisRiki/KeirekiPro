package resume

import (
	"strings"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// defaultFileName は、名前が空白だけのときと、使えない字を除いて何も残らないときのファイル名である。
const defaultFileName = "resume"

// maxFileNameUnits は、ファイル名の長さの上限である。Java 版と同じく UTF-16 の単位で数える。
const maxFileNameUnits = 255

// sanitizeFileName は、経歴書の名前からファイル名を作る。Java 版の FileUtil.sanitizeFileName を写した。
// 空白は Java の String.isBlank、前後の除き方は String.trim、制御の字は正規表現の \p{Cntrl} と同じ範囲にする。
func sanitizeFileName(raw string) string {
	if !auth.NotBlank(raw) {
		return defaultFileName
	}
	name := strings.TrimFunc(raw, func(r rune) bool { return r <= ' ' })
	name = strings.Map(func(r rune) rune {
		switch {
		case strings.ContainsRune(`\/:*?"<>|`, r):
			return '_'
		case r <= 0x1f || r == 0x7f:
			return -1
		}
		return r
	}, name)
	if onlyUnderscores(name) {
		name = strings.TrimLeft(name, "_")
	}
	if !auth.NotBlank(name) {
		return defaultFileName
	}
	return truncateUTF16(name, maxFileNameUnits)
}

// onlyUnderscores は、Java 版の正規表現 ^_+$ が name に当たるかを返す。この正規表現の $ は、入力の終わりのほかに、
// 入力の最後の行の終わりの字の前にも当たる。制御の字を消したあとに残る行の終わりの字は、U+0085、U+2028、U+2029 である。
func onlyUnderscores(name string) bool {
	rest := strings.TrimLeft(name, "_")
	if rest == name {
		return false
	}
	return rest == "" || rest == "\u0085" || rest == " " || rest == " "
}

// truncateUTF16 は、s を UTF-16 の単位で max 以下に切る。Java の String.substring と同じく、切る位置が絵文字のような
// 2つの単位の字を割るときは、前の半分のサロゲートを残す。Go の文字列では、そのサロゲートを UTF-8 と同じ規則の3バイトで書く。
func truncateUTF16(s string, max int) string {
	units := 0
	for i, r := range s {
		n := 1
		if r >= 0x10000 {
			n = 2
		}
		if units+n > max {
			if units < max {
				hi := 0xD800 + (r-0x10000)>>10
				return s[:i] + string([]byte{0xE0 | byte(hi>>12), 0x80 | byte(hi>>6&0x3F), 0x80 | byte(hi&0x3F)})
			}
			return s[:i]
		}
		units += n
	}
	return s
}
