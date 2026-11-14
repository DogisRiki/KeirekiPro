package users

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/ses"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// testFrontendBaseURL は、確認のメールのリンクの先頭である。
const testFrontendBaseURL = "http://localhost:5173"

// recordingSES は、SendEmail に渡された値を覚え、err が nil でなければ err を返す偽の SES のクライアントである。
type recordingSES struct {
	got []*ses.SendEmailInput
	err error
}

func (r *recordingSES) SendEmail(_ context.Context, in *ses.SendEmailInput, _ ...func(*ses.Options)) (*ses.SendEmailOutput, error) {
	r.got = append(r.got, in)
	if r.err != nil {
		return nil, r.err
	}
	return &ses.SendEmailOutput{}, nil
}

// verificationEnv は、確認のメールのテストの部品の束である。
type verificationEnv struct {
	users  *Service
	auth   *auth.Service
	mailer *recordingSES
	redis  redis.UniversalClient
}

// newVerificationEnv は、テストの Postgres と Valkey と偽の SES につなぎ、今の時刻を testNow にした部品を作る。
// 署名の鍵は、テストごとに乱数で作る。
func newVerificationEnv(t *testing.T) verificationEnv {
	t.Helper()
	templates, err := backend.MailTemplates()
	if err != nil {
		t.Fatal(err)
	}
	client := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	t.Cleanup(func() { _ = client.Close() })
	mailer := &recordingSES{}
	now := func() time.Time { return testNow }
	a := auth.New(auth.Deps{
		Pool:  testPool,
		Redis: client,
		SES:   mailer,
		App: config.App{
			ApplicationName: "KeirekiPro",
			FrontendBaseURL: testFrontendBaseURL,
			SESFromAddress:  "noreply@example.com",
		},
		MailTemplates: templates,
		JWT:           config.JWT{Secret: uuid.NewString()},
		Now:           now,
	})
	return verificationEnv{
		users:  New(Deps{Pool: testPool, Redis: client, Auth: a, Now: now}),
		auth:   a,
		mailer: mailer,
		redis:  client,
	}
}

// forgetRecords は、テストの終わりに、利用者 id の今のリンクの記録と、addresses の送り直せる間隔の記録を消す。
func (e verificationEnv) forgetRecords(t *testing.T, id uuid.UUID, addresses ...string) {
	t.Helper()
	keys := []string{"email-verification:current:" + id.String()}
	for _, a := range addresses {
		keys = append(keys, "email-verification:rate:"+a)
	}
	t.Cleanup(func() { e.redis.Del(context.Background(), keys...) })
}

// mailedTo は、偽の SES が i 番目に受けたメールの宛先を返す。
func (e verificationEnv) mailedTo(t *testing.T, i int) []string {
	t.Helper()
	if len(e.mailer.got) <= i {
		t.Fatalf("SendEmail の呼び出し = %d 回、期待 = %d 回以上", len(e.mailer.got), i+1)
	}
	return e.mailer.got[i].Destination.ToAddresses
}

// mailedToken は、偽の SES が i 番目に受けたメールの確認のリンクの # のあとの値を返す。
func (e verificationEnv) mailedToken(t *testing.T, i int) string {
	t.Helper()
	e.mailedTo(t, i)
	body := aws.ToString(e.mailer.got[i].Message.Body.Text.Data)
	_, rest, ok := strings.Cut(body, testFrontendBaseURL+"/email/verify#")
	if !ok {
		t.Fatalf("本文 %q に確認のリンクが無い", body)
	}
	token, _, _ := strings.Cut(rest, "\n")
	return strings.TrimSpace(token)
}

// linkClaims は、確認のリンクの値 token の本体の項目のうち、目的と宛先と利用者の ID を読む。署名は確かめない。
type linkClaims struct {
	Purpose string `json:"purpose"`
	Email   string `json:"email"`
	Subject string `json:"sub"`
}

// wantLink は、偽の SES が i 番目に受けたメールのリンクの目的と宛先と利用者の ID が want かを確かめる。
func (e verificationEnv) wantLink(t *testing.T, i int, want linkClaims) {
	t.Helper()
	parts := strings.Split(e.mailedToken(t, i), ".")
	if len(parts) != 3 {
		t.Fatalf("リンクの値が JWT の形でない: %d 個に分かれた", len(parts))
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatal(err)
	}
	var got linkClaims
	if err := json.Unmarshal(payload, &got); err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Errorf("リンクの項目 = %+v、期待 = %+v", got, want)
	}
}

// wantVerifyResult は、確認のリンクの値 token を使った結果の名前が want かを確かめる。
func (e verificationEnv) wantVerifyResult(t *testing.T, token, want string) {
	t.Helper()
	r, err := e.auth.VerifyEmail(t.Context(), token)
	if err != nil {
		t.Fatalf("VerifyEmail: %v", err)
	}
	if r.Result != want {
		t.Errorf("リンクを使った結果 = %s、期待 = %s", r.Result, want)
	}
}

// wantBusinessError は、err が、文言 message の、項目ごとの文言を持たない 400 の誤りかを確かめる。
func wantBusinessError(t *testing.T, err error, message string) {
	t.Helper()
	var e *auth.Error
	if !errors.As(err, &e) {
		t.Fatalf("誤り = %v、期待 = 400 %q", err, message)
	}
	if e.Status != 400 || e.Message != message || e.Errors == nil || len(e.Errors) != 0 || e.ClearSession {
		t.Errorf("誤り = %d %q %v Cookie を消す=%v、期待 = 400 %q {}", e.Status, e.Message, e.Errors, e.ClearSession, message)
	}
}

func TestSendAccountEmailVerification_PendingEmailFirst(t *testing.T) {
	tests := []struct {
		name string
		row  userRow
		// promotes は、リンクを使うと設定待ちのメールアドレスがメールアドレスになるかである。
		// 認証の処理は、メールアドレスを持つ利用者の設定待ちのメールアドレスを移さない。
		promotes bool
	}{
		{"メールアドレスの確認が済んでいない", userRow{Email: someText("a@example.com")}, false},
		{"メールアドレスの確認が済んでいる", userRow{Email: someText("a@example.com"), EmailVerifiedAt: oldStamp}, false},
		{"メールアドレスが無い", userRow{}, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := newVerificationEnv(t)
			pending := uuid.NewString() + "@example.com"
			tt.row.PendingEmail = someText(pending)
			id := insertUser(t, tt.row)
			e.forgetRecords(t, id, pending, loadUser(t, id).Row.Email.String)

			if err := e.users.SendAccountEmailVerification(t.Context(), id); err != nil {
				t.Fatalf("SendAccountEmailVerification: %v", err)
			}
			if got := e.mailedTo(t, 0); !slices.Equal(got, []string{pending}) || len(e.mailer.got) != 1 {
				t.Fatalf("宛先 = %v、送った数 = %d、期待 = [%s] に1通", got, len(e.mailer.got), pending)
			}
			e.wantLink(t, 0, linkClaims{Purpose: "PENDING_EMAIL", Email: pending, Subject: id.String()})
			if !tt.promotes {
				return
			}
			e.wantVerifyResult(t, e.mailedToken(t, 0), "VERIFIED")
			after := loadUser(t, id)
			if after.Row.Email.String != pending || after.Row.PendingEmail.Valid {
				t.Errorf("メールアドレス = %v、設定待ち = %v、期待 = %s と設定待ち無し", after.Row.Email, after.Row.PendingEmail, pending)
			}
		})
	}
}

func TestSendAccountEmailVerification_AccountEmail(t *testing.T) {
	e := newVerificationEnv(t)
	id := insertUser(t, userRow{Email: someText("a@example.com"), Password: someText("$2a$10$hash")})
	email := loadUser(t, id).Row.Email.String
	e.forgetRecords(t, id, email)

	if err := e.users.SendAccountEmailVerification(t.Context(), id); err != nil {
		t.Fatalf("SendAccountEmailVerification: %v", err)
	}
	if got := e.mailedTo(t, 0); !slices.Equal(got, []string{email}) || len(e.mailer.got) != 1 {
		t.Fatalf("宛先 = %v、送った数 = %d、期待 = [%s] に1通", got, len(e.mailer.got), email)
	}
	e.wantLink(t, 0, linkClaims{Purpose: "ACCOUNT_EMAIL", Email: email, Subject: id.String()})
	e.wantVerifyResult(t, e.mailedToken(t, 0), "VERIFIED")
	after := loadUser(t, id)
	if after.Row.Email.String != email || !after.Row.EmailVerifiedAt.Valid {
		t.Errorf("メールアドレス = %v、確認の日時 = %v、期待 = %s と確認済み", after.Row.Email, after.Row.EmailVerifiedAt, email)
	}
}

func TestSendAccountEmailVerification_NothingToVerify(t *testing.T) {
	tests := []struct {
		name string
		row  userRow
	}{
		{"メールアドレスの確認が済んでいる", userRow{Email: someText("a@example.com"), EmailVerifiedAt: oldStamp}},
		{"メールアドレスも設定待ちのメールアドレスも無い", userRow{Password: someText("$2a$10$hash")}},
		{"確認の日時はあるがメールアドレスが無い", userRow{EmailVerifiedAt: oldStamp}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := newVerificationEnv(t)
			id := insertUser(t, tt.row)
			before := loadUser(t, id)
			e.forgetRecords(t, id, before.Row.Email.String)

			wantBusinessError(t, e.users.SendAccountEmailVerification(t.Context(), id), MessageNothingToVerify)
			if len(e.mailer.got) != 0 {
				t.Errorf("送った数 = %d、期待 = 0", len(e.mailer.got))
			}
			wantUnchanged(t, id, before)
		})
	}
}

func TestSendAccountEmailVerification_RateLimited(t *testing.T) {
	e := newVerificationEnv(t)
	id := insertUser(t, userRow{Email: someText("a@example.com")})
	e.forgetRecords(t, id, loadUser(t, id).Row.Email.String)

	if err := e.users.SendAccountEmailVerification(t.Context(), id); err != nil {
		t.Fatalf("1回目の SendAccountEmailVerification: %v", err)
	}
	wantBusinessError(t, e.users.SendAccountEmailVerification(t.Context(), id), MessageResendRateLimited)
	if len(e.mailer.got) != 1 {
		t.Errorf("送った数 = %d、期待 = 1", len(e.mailer.got))
	}
	// 断った2回目は、1回目のリンクを使えなくしない
	e.wantVerifyResult(t, e.mailedToken(t, 0), "VERIFIED")
}

func TestSendAccountEmailVerification_ReplacesPreviousLink(t *testing.T) {
	e := newVerificationEnv(t)
	id := insertUser(t, userRow{Email: someText("a@example.com")})
	email := loadUser(t, id).Row.Email.String
	e.forgetRecords(t, id, email)

	if err := e.users.SendAccountEmailVerification(t.Context(), id); err != nil {
		t.Fatalf("1回目の SendAccountEmailVerification: %v", err)
	}
	// 送り直せる間隔が過ぎたことにする
	if err := e.redis.Del(t.Context(), "email-verification:rate:"+email).Err(); err != nil {
		t.Fatal(err)
	}
	if err := e.users.SendAccountEmailVerification(t.Context(), id); err != nil {
		t.Fatalf("2回目の SendAccountEmailVerification: %v", err)
	}
	first, second := e.mailedToken(t, 0), e.mailedToken(t, 1)
	if first == second {
		t.Fatal("1回目と2回目のリンクが同じ")
	}
	e.wantVerifyResult(t, first, "EXPIRED")
	e.wantVerifyResult(t, second, "VERIFIED")
}

// TestSendAccountEmailVerification_SendFails は、SES が誤りを返すと、送り直せる間隔の 400 にせず、その誤りを返すことを確かめる。
func TestSendAccountEmailVerification_SendFails(t *testing.T) {
	e := newVerificationEnv(t)
	sesErr := errors.New("SES が断った")
	e.mailer.err = sesErr
	id := insertUser(t, userRow{Email: someText("a@example.com")})
	e.forgetRecords(t, id, loadUser(t, id).Row.Email.String)

	if err := e.users.SendAccountEmailVerification(t.Context(), id); !errors.Is(err, sesErr) {
		t.Errorf("誤り = %v、期待 = %v", err, sesErr)
	}
}

func TestSendAccountEmailVerification_UserGone(t *testing.T) {
	e := newVerificationEnv(t)
	err := e.users.SendAccountEmailVerification(t.Context(), uuid.New())
	var ae *auth.Error
	if !errors.As(err, &ae) {
		t.Fatalf("誤り = %v、期待 = 401 の誤り", err)
	}
	if ae.Status != 401 || ae.Message != MessageInvalidAccess || len(ae.Errors) != 0 || !ae.ClearSession {
		t.Errorf("誤り = %d %q %v Cookie を消す=%v、期待 = 401 %q {} Cookie を消す", ae.Status, ae.Message, ae.Errors, ae.ClearSession, MessageInvalidAccess)
	}
	if len(e.mailer.got) != 0 {
		t.Errorf("送った数 = %d、期待 = 0", len(e.mailer.got))
	}
}
