package backend

import (
	"io/fs"
	"testing"
)

// 埋め込んだメールのひな形から、認証の操作が使う4つのファイルを読めることを確かめる。
func TestMailTemplates_FourFilesReadable(t *testing.T) {
	templates, err := MailTemplates()
	if err != nil {
		t.Fatalf("MailTemplates: %v", err)
	}
	for _, name := range []string{
		"email-verification.ftl",
		"password-reset.ftl",
		"two-factor-auth.ftl",
		"user-registered.ftl",
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
