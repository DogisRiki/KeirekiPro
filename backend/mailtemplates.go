package backend

import (
	"embed"
	"io/fs"
)

// mailTemplateDir は、メールのひな形を置くフォルダである。
const mailTemplateDir = "assets/mail"

//go:embed assets/mail/*.txt
var mailTemplateFiles embed.FS

// MailTemplates は、埋め込んだメールのひな形を、フォルダの最上位に置いた形で返す。
func MailTemplates() (fs.FS, error) {
	return fs.Sub(mailTemplateFiles, mailTemplateDir)
}
