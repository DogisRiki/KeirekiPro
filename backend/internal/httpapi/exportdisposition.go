package httpapi

import (
	"net/url"
	"strings"
)

// formatContentDisposition は、出力の答えの Content-Disposition のヘッダを作る。inline が真なら種類を inline に、
// 偽なら attachment にする。RFC 6266 の 4.3 の勧めのとおり、ASCII の字だけで書いた filename と、RFC 5987 の書き方で
// UTF-8 の名前を書いた filename* の両方を書く。画面は filename* を読む。
//
// filename* では、英数字と - _ . ~ のほかの字をすべて % で書く。画面の読み方は filename* の値を ; で切るので、
// ; も % で書く。UTF-8 として正しくないバイトは ? に替える。filename では、ASCII の表示できる字のほかの字と、
// " と \ を _ に替える。
func formatContentDisposition(inline bool, fileName string) string {
	kind := "attachment"
	if inline {
		kind = "inline"
	}
	name := strings.ToValidUTF8(fileName, "?")
	fallback := strings.Map(func(r rune) rune {
		if r < 0x20 || r > 0x7e || r == '"' || r == '\\' {
			return '_'
		}
		return r
	}, name)
	// url.QueryEscape は空白を + で書くので、%20 に替える。名前の中の + は %2B で書かれるので、取り違えない
	encoded := strings.ReplaceAll(url.QueryEscape(name), "+", "%20")
	return kind + `; filename="` + fallback + `"; filename*=UTF-8''` + encoded
}
