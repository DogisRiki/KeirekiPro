package auth

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// newEmailVerificationService は、テストの Valkey と偽の SES と、Java 版の開発環境と同じ設定の値と鍵を使い、
// 今の時刻を now に決めた Service と、Redis に直に読み書きするクライアントと、偽の SES を作る。
// random が nil なら、本番と同じ乱数を使う。
func newEmailVerificationService(t *testing.T, now time.Time, random func([]byte) (int, error)) (*Service, redis.UniversalClient, *fakeSES) {
	t.Helper()
	templates, err := backend.MailTemplates()
	if err != nil {
		t.Fatal(err)
	}
	client := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	t.Cleanup(func() { _ = client.Close() })
	mailer := &fakeSES{}
	return New(Deps{
		Redis:         client,
		SES:           mailer,
		App:           javaDevApp(t),
		MailTemplates: templates,
		JWT:           config.JWT{Secret: javaDevSigningKey},
		Now:           func() time.Time { return now },
		Random:        random,
	}), client, mailer
}

// mailedBody は、偽の SES が i 番目に受けたメールの本文を返す。
func mailedBody(t *testing.T, mailer *fakeSES, i int) string {
	t.Helper()
	if len(mailer.got) <= i {
		t.Fatalf("SendEmail の呼び出し = %d 回, want %d 回以上", len(mailer.got), i+1)
	}
	return deref(mailer.got[i].Message.Body.Text.Data)
}

// mailedToken は、偽の SES が i 番目に受けたメールの確認のリンクの # のあとの値を返す。
func mailedToken(t *testing.T, mailer *fakeSES, i int) string {
	t.Helper()
	body := mailedBody(t, mailer, i)
	_, rest, ok := strings.Cut(body, "http://localhost:5173/email/verify#")
	if !ok {
		t.Fatalf("本文 %q に確認のリンクが無い", body)
	}
	token, _, _ := strings.Cut(rest, "\n")
	return strings.TrimSpace(token)
}

// mustSend は、確認のメールを送り、送れたことを確かめる。
func mustSend(t *testing.T, s *Service, email string, subject uuid.UUID, purpose emailVerificationPurpose) {
	t.Helper()
	sent, err := s.sendEmailVerification(t.Context(), email, subject, purpose)
	if err != nil || !sent {
		t.Fatalf("sendEmailVerification = %v, %v, want 送れた", sent, err)
	}
}

// TestEmailVerificationToken_SendMatchesJavaMail は、Java 版と同じ鍵と時刻と乱数と宛先で確認のメールを送ると、
// Java 版が送ったメールと同じメールを送り、今のリンクの記録と送り直せる間隔の記録を Java 版と同じ形で置くことを確かめる。
func TestEmailVerificationToken_SendMatchesJavaMail(t *testing.T) {
	jti := uuid.MustParse(javaSampleJTI)
	s, client, mailer := newEmailVerificationService(t, time.Unix(javaSampleIssuedAt, 250_000_000), fixedRandom(jti[:]))
	subject := uuid.MustParse(javaSampleSubject)
	currentKey := "email-verification:current:" + javaSampleSubject
	rateKey := "email-verification:rate:" + javaSampleEmail
	t.Cleanup(func() { client.Del(t.Context(), currentKey, rateKey) })

	mustSend(t, s, javaSampleEmail, subject, purposeRegistration)

	var want struct {
		To      []string `json:"to"`
		Subject string   `json:"subject"`
		Body    string   `json:"body"`
	}
	readMailJSON(t, "email-verification.json", &want)
	in := mailer.got[0]
	if strings.Join(in.Destination.ToAddresses, ",") != strings.Join(want.To, ",") {
		t.Errorf("宛先 = %v, want %v", in.Destination.ToAddresses, want.To)
	}
	if got := deref(in.Message.Subject.Data); got != want.Subject {
		t.Errorf("件名 = %q, want %q", got, want.Subject)
	}
	if got := mailedBody(t, mailer, 0); got != want.Body {
		t.Errorf("本文 = %q\nwant %q", got, want.Body)
	}
	if got := rawValue(t, client, currentKey); got != `"`+javaSampleJTI+`"` {
		t.Errorf("今のリンクの記録 = %q, want %q", got, `"`+javaSampleJTI+`"`)
	}
	assertTTL(t, client, currentKey, 24*time.Hour)
	if got := rawValue(t, client, rateKey); got != `"1"` {
		t.Errorf("送り直せる間隔の記録 = %q, want %q", got, `"1"`)
	}
	assertTTL(t, client, rateKey, 60*time.Second)
}

// TestEmailVerificationToken_TTLByPurpose は、目的ごとに、リンクの値の lexp と今のリンクの記録の有効な時間と
// メールに書くリンクの有効な時間が、Java 版と同じ長さになることを確かめる(要件3の受入基準3)。
func TestEmailVerificationToken_TTLByPurpose(t *testing.T) {
	now := time.Date(2026, 11, 11, 4, 5, 6, 700_000_000, time.UTC)
	cases := []struct {
		purpose  emailVerificationPurpose
		validity time.Duration
		lifetime string
	}{
		{purposeRegistration, 24 * time.Hour, "24時間"},
		{purposeAccountEmail, 24 * time.Hour, "24時間"},
		{purposePendingEmail, 24 * time.Hour, "24時間"},
		{purposePasswordReset, 10 * time.Minute, "10分"},
	}
	for _, tc := range cases {
		t.Run(string(tc.purpose), func(t *testing.T) {
			s, client, mailer := newEmailVerificationService(t, now, nil)
			email, subject := uniqueEmail(), uuid.New()
			mustSend(t, s, email, subject, tc.purpose)

			claims, ok := s.readEmailVerificationToken(mailedToken(t, mailer, 0))
			if !ok {
				t.Fatal("送ったリンクの値を読めない")
			}
			if claims.Purpose != tc.purpose || claims.Email != email || claims.SubjectID != subject {
				t.Errorf("リンクの値の項目 = %+v, want 目的 %s、宛先 %s、ID %s", claims, tc.purpose, email, subject)
			}
			if want := time.Unix(now.Add(tc.validity).Unix(), 0); !claims.LinkExpiresAt.Equal(want) {
				t.Errorf("リンクの期限 = %v, want %v", claims.LinkExpiresAt, want)
			}
			currentKey := "email-verification:current:" + subject.String()
			if got := rawValue(t, client, currentKey); got != `"`+claims.JTI+`"` {
				t.Errorf("今のリンクの記録 = %q, want リンクの jti %q", got, claims.JTI)
			}
			if _, err := uuid.Parse(claims.JTI); err != nil {
				t.Errorf("jti %q が UUID でない", claims.JTI)
			}
			assertTTL(t, client, currentKey, tc.validity)
			if body := mailedBody(t, mailer, 0); !strings.Contains(body, "受信後から"+tc.lifetime+"以内") {
				t.Errorf("本文 %q に有効な時間 %q が無い", body, tc.lifetime)
			}
		})
	}
}

// TestEmailVerificationToken_NewLinkReplacesOld は、新しいリンクを送ると、今のリンクの記録が新しいリンクの jti に
// 置き換わり、前のリンクの jti では消し込めなくなることを確かめる(要件3の受入基準3)。
// また、消し込みは同じ jti で1回だけ成り立ち、記録を消すと読めなくなることを確かめる。
func TestEmailVerificationToken_NewLinkReplacesOld(t *testing.T) {
	ctx := t.Context()
	s, _, mailer := newEmailVerificationService(t, time.Now(), nil)
	email, subject := uniqueEmail(), uuid.New()

	mustSend(t, s, email, subject, purposeRegistration)
	if err := s.releaseEmailVerificationSend(ctx, email); err != nil {
		t.Fatal(err)
	}
	mustSend(t, s, email, subject, purposeRegistration)
	oldClaims, ok1 := s.readEmailVerificationToken(mailedToken(t, mailer, 0))
	newClaims, ok2 := s.readEmailVerificationToken(mailedToken(t, mailer, 1))
	if !ok1 || !ok2 || oldClaims.JTI == newClaims.JTI {
		t.Fatalf("2つのリンクの jti = %q と %q, want 読めて違う値", oldClaims.JTI, newClaims.JTI)
	}

	if got, found, err := s.findCurrentEmailVerification(ctx, subject); err != nil || !found || got != newClaims.JTI {
		t.Errorf("今のリンク = %q, %v, %v, want 新しいリンクの jti %q", got, found, err, newClaims.JTI)
	}
	if consumed, err := s.consumeCurrentEmailVerification(ctx, subject, oldClaims.JTI); err != nil || consumed {
		t.Errorf("前のリンクの消し込み = %v, %v, want 消し込めない", consumed, err)
	}
	if got, found, _ := s.findCurrentEmailVerification(ctx, subject); !found || got != newClaims.JTI {
		t.Errorf("前のリンクで消し込もうとしたあとの今のリンク = %q, %v, want %q のまま", got, found, newClaims.JTI)
	}
	if consumed, err := s.consumeCurrentEmailVerification(ctx, subject, newClaims.JTI); err != nil || !consumed {
		t.Errorf("新しいリンクの消し込み = %v, %v, want 消し込める", consumed, err)
	}
	if consumed, err := s.consumeCurrentEmailVerification(ctx, subject, newClaims.JTI); err != nil || consumed {
		t.Errorf("同じリンクの2回目の消し込み = %v, %v, want 消し込めない", consumed, err)
	}
	if got, found, err := s.findCurrentEmailVerification(ctx, subject); err != nil || found {
		t.Errorf("消し込んだあとの今のリンク = %q, %v, %v, want 無い", got, found, err)
	}

	if err := s.putCurrentEmailVerification(ctx, subject, "x", time.Minute); err != nil {
		t.Fatal(err)
	}
	if err := s.clearCurrentEmailVerification(ctx, subject); err != nil {
		t.Fatal(err)
	}
	if got, found, err := s.findCurrentEmailVerification(ctx, subject); err != nil || found {
		t.Errorf("消したあとの今のリンク = %q, %v, %v, want 無い", got, found, err)
	}
}

// TestEmailVerificationRate_60Seconds は、同じメールアドレスへは60秒のあいだ送り直せず、そのあいだは何も置かずに
// 送れないと返し、ほかのメールアドレスへは送れることを確かめる(要件3の受入基準4)。
func TestEmailVerificationRate_60Seconds(t *testing.T) {
	ctx := t.Context()
	s, client, mailer := newEmailVerificationService(t, time.Now(), nil)
	email, first, second := uniqueEmail(), uuid.New(), uuid.New()
	rateKey := "email-verification:rate:" + email

	mustSend(t, s, email, first, purposeRegistration)
	assertTTL(t, client, rateKey, 60*time.Second)

	sent, err := s.sendEmailVerification(ctx, email, second, purposeAccountEmail)
	if err != nil || sent {
		t.Errorf("60秒のあいだの送り直し = %v, %v, want 送れない", sent, err)
	}
	if len(mailer.got) != 1 {
		t.Errorf("SendEmail の呼び出し = %d 回, want 1 回", len(mailer.got))
	}
	if keyExists(t, client, "email-verification:current:"+second.String()) {
		t.Error("送れなかったのに、今のリンクの記録が置かれた")
	}
	assertTTL(t, client, rateKey, 60*time.Second)

	mustSend(t, s, uniqueEmail(), second, purposeAccountEmail)

	if err := s.releaseEmailVerificationSend(ctx, email); err != nil {
		t.Fatal(err)
	}
	mustSend(t, s, email, second, purposeAccountEmail)
	if len(mailer.got) != 3 {
		t.Errorf("SendEmail の呼び出し = %d 回, want 3 回", len(mailer.got))
	}
}

// TestEmailVerificationRate_ReleasedWhenMailFails は、メールを送れないとき、送り直せる間隔の記録と今のリンクの記録を
// 消して誤りを返し、すぐに送り直せることを確かめる。前に送ったリンクも使えなくなる(Java 版も同じ)。
func TestEmailVerificationRate_ReleasedWhenMailFails(t *testing.T) {
	ctx := t.Context()
	s, client, mailer := newEmailVerificationService(t, time.Now(), nil)
	email, subject := uniqueEmail(), uuid.New()
	currentKey := "email-verification:current:" + subject.String()
	if err := s.putCurrentEmailVerification(ctx, subject, "earlier-jti", time.Hour); err != nil {
		t.Fatal(err)
	}

	sesErr := errors.New("SES に届かない")
	mailer.err = sesErr
	sent, err := s.sendEmailVerification(ctx, email, subject, purposeRegistration)
	if !errors.Is(err, sesErr) || sent {
		t.Errorf("sendEmailVerification = %v, %v, want SES の誤り", sent, err)
	}
	if keyExists(t, client, "email-verification:rate:"+email) {
		t.Error("送れなかったのに、送り直せる間隔の記録が残った")
	}
	if keyExists(t, client, currentKey) {
		t.Error("送れなかったのに、今のリンクの記録が残った")
	}

	mailer.err = nil
	mustSend(t, s, email, subject, purposeRegistration)
}
