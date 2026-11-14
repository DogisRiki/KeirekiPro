package auth

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"strings"
	"testing"
	"testing/fstest"

	"github.com/aws/aws-sdk-go-v2/service/ses"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
)

// testdata/mail の正解のファイルは、開発環境の Java 版に4種類のメールを送らせ、LocalStack の SES が受けたメールを
// 書き写したものである。Java 版は、利用者の登録、確認のリンクを開く操作、2段階認証を有効にした利用者のログイン、
// パスワードの再設定の求めの順に呼んだ。<種類>.json が SES の受けた送り主と宛先と件名と本文で、
// <種類>.values.json が Java 版がそのメールに差し込んだ値で、app.json が Java 版の開発環境の設定の値である。
// 利用者の名前には、HTML の特別な文字と、ひな形の書き方に似た文字を入れてある。Java 版はそのまま差し込む。

// fakeSES は、SendEmail に渡された値を覚え、決めた誤りを返す偽の SES のクライアントである。
type fakeSES struct {
	got []*ses.SendEmailInput
	err error
}

func (f *fakeSES) SendEmail(_ context.Context, in *ses.SendEmailInput, _ ...func(*ses.Options)) (*ses.SendEmailOutput, error) {
	f.got = append(f.got, in)
	if f.err != nil {
		return nil, f.err
	}
	return &ses.SendEmailOutput{}, nil
}

// readMailJSON は、testdata/mail の JSON のファイルを v に読む。
func readMailJSON(t *testing.T, name string, v any) {
	t.Helper()
	b, err := fs.ReadFile(os.DirFS("testdata/mail"), name)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(b, v); err != nil {
		t.Fatalf("%s: %v", name, err)
	}
}

// javaDevApp は、正解のファイルを作ったときの Java 版の開発環境の設定の値を、Go の設定の形で返す。
func javaDevApp(t *testing.T) config.App {
	t.Helper()
	var a struct {
		ApplicationName string `json:"applicationName"`
		FrontendBaseURL string `json:"frontendBaseUrl"`
		SESFromAddress  string `json:"sesFromAddress"`
		SiteName        string `json:"siteName"`
		SiteURL         string `json:"siteUrl"`
	}
	readMailJSON(t, "app.json", &a)
	return config.App{
		ApplicationName: a.ApplicationName,
		FrontendBaseURL: a.FrontendBaseURL,
		SESFromAddress:  a.SESFromAddress,
		SiteName:        a.SiteName,
		SiteURL:         a.SiteURL,
	}
}

func TestMail_FourKindsMatchJava(t *testing.T) {
	templates, err := backend.MailTemplates()
	if err != nil {
		t.Fatal(err)
	}
	app := javaDevApp(t)
	cases := []struct {
		kind  string
		build func(v map[string]string) mail
	}{
		{"email-verification", func(v map[string]string) mail {
			return emailVerificationMail(app, v["verificationLink"], v["linkLifetime"])
		}},
		{"password-reset", func(v map[string]string) mail { return passwordResetMail(app, v["resetLink"]) }},
		{"two-factor-auth", func(v map[string]string) mail { return twoFactorCodeMail(app, v["code"]) }},
		{"user-registered", func(v map[string]string) mail { return userRegisteredMail(app, v["username"]) }},
	}
	for _, c := range cases {
		t.Run(c.kind, func(t *testing.T) {
			var values map[string]string
			readMailJSON(t, c.kind+".values.json", &values)
			var want struct {
				From    string   `json:"from"`
				To      []string `json:"to"`
				Subject string   `json:"subject"`
				Body    string   `json:"body"`
			}
			readMailJSON(t, c.kind+".json", &want)

			client := &fakeSES{}
			s := New(Deps{SES: client, App: app, MailTemplates: templates})
			if err := s.sendMail(context.Background(), values["to"], c.build(values)); err != nil {
				t.Fatalf("sendMail: %v", err)
			}
			if len(client.got) != 1 {
				t.Fatalf("SendEmail の呼び出し = %d 回, want 1 回", len(client.got))
			}
			in := client.got[0]
			if got := deref(in.Source); got != want.From {
				t.Errorf("送り主 = %q, want %q", got, want.From)
			}
			if in.Destination == nil || strings.Join(in.Destination.ToAddresses, ",") != strings.Join(want.To, ",") ||
				len(in.Destination.CcAddresses) != 0 || len(in.Destination.BccAddresses) != 0 {
				t.Errorf("宛先 = %+v, want To %v だけ", in.Destination, want.To)
			}
			msg := in.Message
			if msg == nil || msg.Subject == nil || msg.Body == nil || msg.Body.Text == nil {
				t.Fatalf("Message = %+v, want 件名と文字の本文がある", msg)
			}
			if got := deref(msg.Subject.Data); got != want.Subject {
				t.Errorf("件名 = %q, want %q", got, want.Subject)
			}
			if got := deref(msg.Body.Text.Data); got != want.Body {
				t.Errorf("本文 = %q\nwant %q", got, want.Body)
			}
			if deref(msg.Subject.Charset) != "UTF-8" || deref(msg.Body.Text.Charset) != "UTF-8" {
				t.Errorf("文字の符号 = 件名 %q 本文 %q, want UTF-8", deref(msg.Subject.Charset), deref(msg.Body.Text.Charset))
			}
			if msg.Body.Html != nil {
				t.Errorf("HTML の本文 = %+v, want 無し", msg.Body.Html)
			}
		})
	}
}

func deref(p *string) string {
	if p == nil {
		return "<nil>"
	}
	return *p
}

func TestMail_RejectsOtherTemplateSyntax(t *testing.T) {
	bad := map[string]string{
		"ドルだけ":         "金額は $5 です\n",
		"波括弧の無いドル":     "${a}と$a\n",
		"閉じないドル":       "${a\n",
		"名前でない差し込み":    "${a.b}\n",
		"空の差し込み":       "${}\n",
		"関数の呼び出し":      "${a?upper_case}\n",
		"Go のひな形の書き方":  "{{.a}}\n",
		"Go のひな形の開始だけ": "{{\n",
		"波括弧で囲んだ差し込み":  "{${a}}\n",
	}
	for name, body := range bad {
		t.Run(name, func(t *testing.T) {
			fsys := fstest.MapFS{"x.ftl": {Data: []byte(body)}}
			client := &fakeSES{}
			s := New(Deps{SES: client, MailTemplates: fsys})
			err := s.sendMail(context.Background(), "a@example.com", mail{template: "x.ftl", subject: "s", values: map[string]string{"a": "1"}})
			if err == nil {
				t.Fatalf("sendMail(%q) = nil, want 誤り", body)
			}
			if len(client.got) != 0 {
				t.Errorf("SendEmail が呼ばれた, want 呼ばれない")
			}
		})
	}

	t.Run("差し込む値が無い", func(t *testing.T) {
		fsys := fstest.MapFS{"x.ftl": {Data: []byte("${a}${b}\n")}}
		client := &fakeSES{}
		s := New(Deps{SES: client, MailTemplates: fsys})
		err := s.sendMail(context.Background(), "a@example.com", mail{template: "x.ftl", subject: "s", values: map[string]string{"a": "1"}})
		if err == nil || len(client.got) != 0 {
			t.Fatalf("sendMail = %v, 呼び出し %d 回, want 誤りで呼ばれない", err, len(client.got))
		}
	})

	t.Run("ひな形が無い", func(t *testing.T) {
		client := &fakeSES{}
		s := New(Deps{SES: client, MailTemplates: fstest.MapFS{}})
		err := s.sendMail(context.Background(), "a@example.com", mail{template: "x.ftl", subject: "s"})
		if err == nil || len(client.got) != 0 {
			t.Fatalf("sendMail = %v, 呼び出し %d 回, want 誤りで呼ばれない", err, len(client.got))
		}
	})

	t.Run("差し込みだけのひな形は値をそのまま差し込む", func(t *testing.T) {
		fsys := fstest.MapFS{"x.ftl": {Data: []byte("[${a}] }} ${b}\n")}}
		client := &fakeSES{}
		s := New(Deps{SES: client, MailTemplates: fsys})
		err := s.sendMail(context.Background(), "a@example.com",
			mail{template: "x.ftl", subject: "s", values: map[string]string{"a": "<&>{{.b}}", "b": "${a}"}})
		if err != nil {
			t.Fatal(err)
		}
		if len(client.got) != 1 {
			t.Fatalf("SendEmail の呼び出し = %d 回, want 1 回", len(client.got))
		}
		if got := deref(client.got[0].Message.Body.Text.Data); got != "[<&>{{.b}}] }} ${a}\n" {
			t.Errorf("本文 = %q", got)
		}
	})
}

func TestMail_WrapsSESError(t *testing.T) {
	templates, err := backend.MailTemplates()
	if err != nil {
		t.Fatal(err)
	}
	sesErr := errors.New("ses down")
	client := &fakeSES{err: sesErr}
	s := New(Deps{SES: client, App: javaDevApp(t), MailTemplates: templates})
	err = s.sendMail(context.Background(), "a@example.com", twoFactorCodeMail(s.deps.App, "123456"))
	if !errors.Is(err, sesErr) {
		t.Fatalf("sendMail = %v, want ses の誤りを包む", err)
	}
	if len(client.got) != 1 {
		t.Errorf("SendEmail の呼び出し = %d 回, want 1 回(再試行しない)", len(client.got))
	}
}

// testdata/mail/user-deleted.txt と user-deleted.json と user-deleted.values.json は、開発環境の Java 版で、確認の済んだメールアドレス
// cap-mail@example.com と名前「退会太郎」を持つ利用者を退会させ、LocalStack の SES が受けたメールを書き写したものである。
// user-deleted.txt は、1行目が件名で、空の行を1つはさんで、3行目から最後までが本文である。
// user-deleted.values.json は、Java 版がそのメールに差し込んだ宛先と名前である。

// userDeletedJava は、Java 版が送った退会の完了のメールの件名と本文と宛先と送り主と、差し込んだ名前である。
type userDeletedJava struct {
	subject, body, to, from, username string
}

func readUserDeletedJava(t *testing.T) userDeletedJava {
	t.Helper()
	b, err := fs.ReadFile(os.DirFS("testdata/mail"), "user-deleted.txt")
	if err != nil {
		t.Fatal(err)
	}
	subject, body, ok := strings.Cut(string(b), "\n\n")
	if !ok {
		t.Fatal("user-deleted.txt に件名と本文の区切りの空の行が無い")
	}
	var rec struct {
		Messages []struct {
			Source      string
			Subject     string
			Destination struct{ ToAddresses []string }
			Body        struct {
				TextPart string  `json:"text_part"`
				HTMLPart *string `json:"html_part"`
			}
		} `json:"messages"`
	}
	readMailJSON(t, "user-deleted.json", &rec)
	if len(rec.Messages) != 1 || len(rec.Messages[0].Destination.ToAddresses) != 1 {
		t.Fatalf("user-deleted.json のメール = %+v, want 宛先が1つのメール1通", rec.Messages)
	}
	var values map[string]string
	readMailJSON(t, "user-deleted.values.json", &values)
	m := rec.Messages[0]
	if m.Destination.ToAddresses[0] != values["to"] || values["username"] == "" {
		t.Fatalf("user-deleted.values.json = %v, want 宛先 %q と名前", values, m.Destination.ToAddresses[0])
	}
	if m.Subject != subject || m.Body.TextPart != body || m.Body.HTMLPart != nil {
		t.Fatal("user-deleted.txt と user-deleted.json の件名か本文が食い違う")
	}
	return userDeletedJava{subject: subject, body: body, to: values["to"], from: m.Source, username: values["username"]}
}

func TestMail_UserDeletedMatchesJava(t *testing.T) {
	templates, err := backend.MailTemplates()
	if err != nil {
		t.Fatal(err)
	}
	want := readUserDeletedJava(t)
	client := &fakeSES{}
	s := New(Deps{SES: client, App: javaDevApp(t), MailTemplates: templates})
	if err := s.SendUserDeletedMail(context.Background(), want.to, pgtype.Text{String: want.username, Valid: true}); err != nil {
		t.Fatalf("SendUserDeletedMail: %v", err)
	}
	if len(client.got) != 1 {
		t.Fatalf("SendEmail の呼び出し = %d 回, want 1 回", len(client.got))
	}
	in := client.got[0]
	if got := deref(in.Source); got != want.from {
		t.Errorf("送り主 = %q, want %q", got, want.from)
	}
	if in.Destination == nil || strings.Join(in.Destination.ToAddresses, ",") != want.to ||
		len(in.Destination.CcAddresses) != 0 || len(in.Destination.BccAddresses) != 0 {
		t.Errorf("宛先 = %+v, want To %q だけ", in.Destination, want.to)
	}
	msg := in.Message
	if msg == nil || msg.Subject == nil || msg.Body == nil || msg.Body.Text == nil {
		t.Fatalf("Message = %+v, want 件名と文字の本文がある", msg)
	}
	if got := deref(msg.Subject.Data); got != want.subject {
		t.Errorf("件名 = %q, want %q", got, want.subject)
	}
	if got := deref(msg.Body.Text.Data); got != want.body {
		t.Errorf("本文 = %q\nwant %q", got, want.body)
	}
	if deref(msg.Subject.Charset) != "UTF-8" || deref(msg.Body.Text.Charset) != "UTF-8" {
		t.Errorf("文字の符号 = 件名 %q 本文 %q, want UTF-8", deref(msg.Subject.Charset), deref(msg.Body.Text.Charset))
	}
	if msg.Body.Html != nil {
		t.Errorf("HTML の本文 = %+v, want 無し", msg.Body.Html)
	}
}

func TestMail_UserDeletedNoUsername(t *testing.T) {
	templates, err := backend.MailTemplates()
	if err != nil {
		t.Fatal(err)
	}
	client := &fakeSES{}
	s := New(Deps{SES: client, App: javaDevApp(t), MailTemplates: templates})
	err = s.SendUserDeletedMail(context.Background(), "a@example.com", pgtype.Text{})
	if err == nil {
		t.Fatal("SendUserDeletedMail(名前が無い) = nil, want 誤り")
	}
	if len(client.got) != 0 {
		t.Errorf("SendEmail の呼び出し = %d 回, want 呼ばれない", len(client.got))
	}
}
