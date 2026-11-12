package backend

import (
	"embed"
	"io/fs"
)

// mailTemplateDir は、Java 版のメールのひな形を置くフォルダである。
const mailTemplateDir = "src/main/resources/mail"

//go:embed src/main/resources/mail/*.ftl
var mailTemplateFiles embed.FS

// MailTemplates は、埋め込んだメールのひな形を、フォルダの最上位に置いた形で返す。
// Go 版は、Java 版と同じひな形のファイルを使い、同じ件名と本文のメールを送る。
func MailTemplates() (fs.FS, error) {
	return fs.Sub(mailTemplateFiles, mailTemplateDir)
}
