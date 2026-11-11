package auth

import (
	"context"
	"fmt"
	"io/fs"
	"regexp"
	"strings"
	"text/template"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/ses"
	"github.com/aws/aws-sdk-go-v2/service/ses/types"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
)

// このファイルは、Java 版の SesFreeMarkerNotificationDispatcher を写す。Java 版と同じひな形のファイル
// (src/main/resources/mail/*.ftl)を読み、${名前} に値を差し込み、文字だけの本文のメールを SES で送る。

// mailCharset は、件名と本文の文字の符号である。
const mailCharset = "UTF-8"

// mailPlaceholder は、ひな形の中の、値を差し込む ${名前} の書き方である。
var mailPlaceholder = regexp.MustCompile(`\$\{([A-Za-z][A-Za-z0-9]*)\}`)

// mail は、送る1通のメールの、ひな形のファイルの名前と、件名と、差し込む値である。
type mail struct {
	template string
	subject  string
	values   map[string]string
}

// emailVerificationMail は、メールアドレスの確認のメールを作る(Java 版の EmailVerificationNotification)。
// link は確認のリンクで、lifetime は「24時間」や「10分」のようなリンクの有効な時間の文である。
func emailVerificationMail(app config.App, link, lifetime string) mail {
	return mail{
		template: "email-verification.ftl",
		subject:  "【" + app.ApplicationName + "】メールアドレスの確認",
		values: map[string]string{
			"verificationLink": link,
			"linkLifetime":     lifetime,
			"siteName":         app.ApplicationName,
			"siteUrl":          app.FrontendBaseURL,
		},
	}
}

// passwordResetMail は、パスワードの再設定のメールを作る(Java 版の PasswordResetNotification)。
func passwordResetMail(app config.App, link string) mail {
	return mail{
		template: "password-reset.ftl",
		subject:  "【" + app.ApplicationName + "】パスワードリセットのご案内",
		values: map[string]string{
			"resetLink": link,
			"siteName":  app.ApplicationName,
			"siteUrl":   app.FrontendBaseURL,
		},
	}
}

// twoFactorCodeMail は、2段階認証の確認のコードのメールを作る(Java 版の TwoFactorCodeNotification)。
func twoFactorCodeMail(app config.App, code string) mail {
	return mail{
		template: "two-factor-auth.ftl",
		subject:  "【" + app.SiteName + "】2段階認証コードのお知らせ",
		values: map[string]string{
			"code":     code,
			"siteName": app.SiteName,
			"siteUrl":  app.SiteURL,
		},
	}
}

// userRegisteredMail は、新規の登録の完了のメールを作る(Java 版の UserRegisteredNotification)。
func userRegisteredMail(app config.App, username string) mail {
	return mail{
		template: "user-registered.ftl",
		subject:  "【" + app.SiteName + "】新規登録完了のお知らせ",
		values: map[string]string{
			"username": username,
			"siteName": app.SiteName,
			"siteUrl":  app.SiteURL,
		},
	}
}

// sendMail は、m のひな形に値を差し込み、送り主を App.SESFromAddress にして to へ SES で送る。
// SES の誤りは包んで返す。Java 版と同じく、送り出しを再試行しない。
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

// loadMailTemplate は、ひな形のファイルを読み、${名前} を text/template の {{.名前}} に置き換えて組み立てる。
// ひな形は FreeMarker の書き方で書かれているが、Go 版は ${名前} の差し込みだけを受け付ける。
// ${名前} のほかの $ と {{ を含むひな形は、Java 版と同じ本文になるとは限らないので、誤りにする。
func loadMailTemplate(fsys fs.FS, name string) (*template.Template, error) {
	src, err := fs.ReadFile(fsys, name)
	if err != nil {
		return nil, fmt.Errorf("メールのひな形 %s を読めない: %w", name, err)
	}
	text := string(src)
	rest := mailPlaceholder.ReplaceAllString(text, "")
	if strings.Contains(rest, "$") || strings.Contains(rest, "{{") {
		return nil, fmt.Errorf("メールのひな形 %s に、${名前} のほかの書き方がある", name)
	}
	converted := mailPlaceholder.ReplaceAllString(text, "{{.$1}}")
	tmpl, err := template.New(name).Option("missingkey=error").Parse(converted)
	if err != nil {
		return nil, fmt.Errorf("メールのひな形 %s を組み立てられない: %w", name, err)
	}
	return tmpl, nil
}
