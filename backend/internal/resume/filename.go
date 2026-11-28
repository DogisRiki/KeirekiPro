package resume

import (
	"strings"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// defaultFileName は、名前が空白だけのときと、使えない字と制御の字を直したあとに _ だけが残るときのファイル名である。
const defaultFileName = "resume"

// maxFileNameRunes は、ファイル名の長さの上限の字の数である。経歴書の名前は50字までなので、ふだんは届かない。
const maxFileNameRunes = 255

// sanitizeFileName は、経歴書の名前からファイル名を作る。
//   - ファイル名に使えない9つの字(\ / : * ? " < > |)を _ にする
//   - ASCII の制御の字(U+0000〜U+001F と U+007F)を消す
//   - 前後の半角の空白を除く
//   - 残りが _ だけか、空白だけなら、defaultFileName にする
//   - 255 字を超えれば、255 字で切る
func sanitizeFileName(raw string) string {
	name := strings.Map(func(r rune) rune {
		switch {
		case strings.ContainsRune(`\/:*?"<>|`, r):
			return '_'
		case r <= 0x1f || r == 0x7f:
			return -1
		}
		return r
	}, raw)
	name = strings.Trim(name, " ")
	if strings.Trim(name, "_") == "" || !auth.NotBlank(name) {
		return defaultFileName
	}
	if runes := []rune(name); len(runes) > maxFileNameRunes {
		return string(runes[:maxFileNameRunes])
	}
	return name
}
