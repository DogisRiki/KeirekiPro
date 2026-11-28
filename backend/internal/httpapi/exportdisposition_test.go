package httpapi

import (
	"mime"
	"testing"
)

// TestFormatContentDisposition は、出し方とファイル名から Content-Disposition のヘッダを作り、ヘッダを読み直すと
// 同じ出し方とファイル名になることを確かめる。
func TestFormatContentDisposition(t *testing.T) {
	cases := []struct {
		name     string
		inline   bool
		fileName string
		want     string
		// readBack は、読み直したファイル名の期待である。空なら fileName と同じである。
		readBack string
	}{
		{name: "ASCII の名前", fileName: "resume.md", want: `attachment; filename="resume.md"; filename*=UTF-8''resume.md`},
		{
			name: "空白と + を含む ASCII の名前", inline: true, fileName: "my resume+1.pdf",
			want: `inline; filename="my resume+1.pdf"; filename*=UTF-8''my%20resume%2B1.pdf`,
		},
		{
			name: "; と % を含む ASCII の名前", fileName: "a;b%c.md",
			want: `attachment; filename="a;b%c.md"; filename*=UTF-8''a%3Bb%25c.md`,
		},
		{
			name: `" と \ を含む名前`, fileName: `a"b\c.md`,
			want: `attachment; filename="a_b_c.md"; filename*=UTF-8''a%22b%5Cc.md`,
		},
		{
			name: "日本語の名前", inline: true, fileName: "職務経歴書.pdf",
			want: `inline; filename="_____.pdf"; filename*=UTF-8''%E8%81%B7%E5%8B%99%E7%B5%8C%E6%AD%B4%E6%9B%B8.pdf`,
		},
		{
			name: "UTF-8 として正しくないバイト", fileName: "a\xed\xa0\x80.pdf",
			want: `attachment; filename="a?.pdf"; filename*=UTF-8''a%3F.pdf`, readBack: "a?.pdf",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := formatContentDisposition(c.inline, c.fileName)
			if got != c.want {
				t.Errorf("ヘッダが\n%s\n、期待は\n%s", got, c.want)
			}
			kind, params, err := mime.ParseMediaType(got)
			if err != nil {
				t.Fatalf("ヘッダ %q を読めない: %v", got, err)
			}
			wantKind := "attachment"
			if c.inline {
				wantKind = "inline"
			}
			wantName := c.fileName
			if c.readBack != "" {
				wantName = c.readBack
			}
			if kind != wantKind || params["filename"] != wantName {
				t.Errorf("読み直した出し方とファイル名が %q と %q、期待は %q と %q", kind, params["filename"], wantKind, wantName)
			}
		})
	}
}
