package auth

import (
	"context"
	"fmt"
	"io/fs"
	"strings"
	"text/template"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/ses"
	"github.com/aws/aws-sdk-go-v2/service/ses/types"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
)

// このファイルは、メールのひな形のファイル(assets/mail/*.txt)を text/template で読み、値を差し込み、
// 文字だけの本文のメールを SES で送る。

// mailCharset は、件名と本文の文字の符号である。
const mailCharset = "UTF-8"

// mail は、送る1通のメールの、ひな形のファイルの名前と、件名と、差し込む値である。
type mail struct {
	template string
	subject  string
	values   map[string]string
}

// emailVerificationMail は、メールアドレスの確認のメールを作る。
// link は確認のリンクで、lifetime は「24時間」や「10分」のようなリンクの有効な時間の文である。
func emailVerificationMail(app config.App, link, lifetime string) mail {
	return mail{
		template: "email-verification.txt",
		subject:  "【" + app.ApplicationName + "】メールアドレスの確認",
		values: map[string]string{
			"verificationLink": link,
			"linkLifetime":     lifetime,
			"siteName":         app.ApplicationName,
			"siteUrl":          app.FrontendBaseURL,
		},
	}
}

// passwordResetMail は、パスワードの再設定のメールを作る。
func passwordResetMail(app config.App, link string) mail {
	return mail{
		template: "password-reset.txt",
		subject:  "【" + app.ApplicationName + "】パスワードリセットのご案内",
		values: map[string]string{
			"resetLink": link,
			"siteName":  app.ApplicationName,
			"siteUrl":   app.FrontendBaseURL,
		},
	}
}

// twoFactorCodeMail は、2段階認証の確認のコードのメールを作る。
func twoFactorCodeMail(app config.App, code string) mail {
	return mail{
		template: "two-factor-auth.txt",
		subject:  "【" + app.SiteName + "】2段階認証コードのお知らせ",
		values: map[string]string{
			"code":     code,
			"siteName": app.SiteName,
			"siteUrl":  app.SiteURL,
		},
	}
}

// userRegisteredMail は、新規の登録の完了のメールを作る。
func userRegisteredMail(app config.App, username string) mail {
	return mail{
		template: "user-registered.txt",
		subject:  "【" + app.SiteName + "】新規登録完了のお知らせ",
		values: map[string]string{
			"username": username,
			"siteName": app.SiteName,
			"siteUrl":  app.SiteURL,
		},
	}
}

// userDeletedMail は、退会の完了のメールを作る。
func userDeletedMail(app config.App, username string) mail {
	return mail{
		template: "user-deleted.txt",
		subject:  "【" + app.SiteName + "】退会手続き完了のお知らせ",
		values: map[string]string{
			"username": username,
			"siteName": app.SiteName,
			"siteUrl":  app.SiteURL,
		},
	}
}

// sendMail は、m のひな形に値を差し込み、送り主を App.SESFromAddress にして to へ SES で送る。
// SES の誤りは包んで返す。送り出しを再試行しない。
func (s *Service) sendMail(ctx context.Context, to string, m mail) error {
	body, err := renderMail(s.deps.MailTemplates, m)
	if err != nil {
		return err
	}
	_, err = s.deps.SES.SendEmail(ctx, &ses.SendEmailInput{
		Source:      aws.String(s.deps.App.SESFromAddress),
		Destination: &types.Destination{ToAddresses: []string{to}},
		Message: &types.Message{
			Subject: &types.Content{Data: aws.String(m.subject), Charset: aws.String(mailCharset)},
			Body: &types.Body{
				Text: &types.Content{Data: aws.String(body), Charset: aws.String(mailCharset)},
			},
		},
	})
	if err != nil {
		return fmt.Errorf("メール %s を送れない: %w", m.template, err)
	}
	return nil
}

// renderMail は、ひな形のファイルを読み、m の値を差し込んだ本文を返す。
func renderMail(fsys fs.FS, m mail) (string, error) {
	tmpl, err := loadMailTemplate(fsys, m.template)
	if err != nil {
		return "", err
	}
	var b strings.Builder
	if err := tmpl.Execute(&b, m.values); err != nil {
		return "", fmt.Errorf("メールのひな形 %s に値を差し込めない: %w", m.template, err)
	}
	return b.String(), nil
}

// loadMailTemplate は、ひな形のファイルを読み、text/template で組み立てる。
// 差し込む値が無い {{.名前}} は、空の文字にせず、差し込むときの誤りにする。
func loadMailTemplate(fsys fs.FS, name string) (*template.Template, error) {
	src, err := fs.ReadFile(fsys, name)
	if err != nil {
		return nil, fmt.Errorf("メールのひな形 %s を読めない: %w", name, err)
	}
	tmpl, err := template.New(name).Option("missingkey=error").Parse(string(src))
	if err != nil {
		return nil, fmt.Errorf("メールのひな形 %s を組み立てられない: %w", name, err)
	}
	return tmpl, nil
}
