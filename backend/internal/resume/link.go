package resume

import (
	"net/url"
	"strings"
)

// isHTTPSLink は、リンクの入力欄の値が、スキームが https で、ホスト名がある URL かを返す。値が空なら true を返す。
// 空の値と空白だけの値は、入力必須の検査が断る。url.Parse はスキームを小文字に直すので、スキームの大文字と小文字は区別しない。
// リンクは、画面の入力欄と PDF と Markdown のどれでも文字として出し、リンクとして開く箇所は無い。
func isHTTPSLink(s string) bool {
	if s == "" {
		return true
	}
	u, err := url.Parse(s)
	return err == nil && u.Scheme == "https" && u.Hostname() != ""
}

// hasHTTPSScheme は、バックアップの戻しのリンクが https: で始まるかを、英字の大文字と小文字を区別せずに返す。
// 戻しは、入力の検査より緩いこの決まりで確かめ、Go 版と Java 版の入力の検査が通したリンクを、どれも戻せるようにする。
// Java 版の入力の検査は、url: を前に付けたリンクも通したので、url: を除いてから確かめる。
func hasHTTPSScheme(s string) bool {
	const urlPrefix, scheme = "url:", "https:"
	if len(s) >= len(urlPrefix) && strings.EqualFold(s[:len(urlPrefix)], urlPrefix) {
		s = s[len(urlPrefix):]
	}
	return len(s) >= len(scheme) && strings.EqualFold(s[:len(scheme)], scheme)
}
