package backend

import (
	"io/fs"
	"testing"
)

// 埋め込んだメールのひな形から、メールを送る操作が使う5つのファイルを読めることを確かめる。
func TestMailTemplates_FiveFilesReadable(t *testing.T) {
	templates, err := MailTemplates()
	if err != nil {
		t.Fatalf("MailTemplates: %v", err)
	}
	for _, name := range []string{
		"email-verification.txt",
		"password-reset.txt",
		"two-factor-auth.txt",
		"user-deleted.txt",
		"user-registered.txt",
	} {
		body, err := fs.ReadFile(templates, name)
		if err != nil {
			t.Errorf("%s を読めません: %v", name, err)
			continue
		}
		if len(body) == 0 {
			t.Errorf("%s が空です", name)
		}
	}
}
