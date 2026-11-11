package auth

import (
	"errors"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
)

const registerPhrase = "Passw0rd!Register"

// registerOne は、新しいメールアドレスで登録を受け付け、そのメールアドレスと、置かれた登録の途中の記録を返す。
func registerOne(t *testing.T, s *Service) (string, pendingRegistration) {
	t.Helper()
	email := uniqueEmail()
	if err := s.Register(t.Context(), RegisterInput{Email: email, Username: "山田<&>太郎", Password: registerPhrase}); err != nil {
		t.Fatalf("Register: %v", err)
	}
	pending, err := s.findPendingRegistrationsByEmail(t.Context(), email, maxPendingRegistrations)
	if err != nil || len(pending) != 1 {
		t.Fatalf("登録の途中の記録 = %+v, %v, want 1つ", pending, err)
	}
	return email, pending[0]
}

// releaseRate は、メールアドレス email の送り直せる間隔の記録を消し、すぐに送り直せるようにする。
func releaseRate(t *testing.T, client redis.UniversalClient, email string) {
	t.Helper()
	if err := client.Del(t.Context(), emailVerificationRateKeyPrefix+email).Err(); err != nil {
		t.Fatal(err)
	}
}

// wantInputError は、err が、項目 email に文言 message を持つ入力の誤りであることを確かめる。
func wantInputError(t *testing.T, err error, message string) {
	t.Helper()
	var e *Error
	if !errors.As(err, &e) {
		t.Fatalf("誤り = %v, want 入力の誤り", err)
	}
	want := &Error{Status: 400, Message: MessageInvalidInput, Errors: map[string][]string{"email": {message}}}
	if !reflect.DeepEqual(e, want) {
		t.Errorf("誤り = %+v, want %+v", e, want)
	}
}

// wantNoPending は、メールアドレス email の登録の途中の記録が無いことを確かめる。
func wantNoPending(t *testing.T, s *Service, email string) {
	t.Helper()
	pending, err := s.findPendingRegistrationsByEmail(t.Context(), email, maxPendingRegistrations)
	if err != nil || len(pending) != 0 {
		t.Errorf("登録の途中の記録 = %+v, %v, want 無い", pending, err)
	}
}

// TestRegister_ThenVerifyEmail は、登録を受け付けると、Java 版と同じ形の登録の途中の記録を24時間置いて確認のメールを送り、
// そのリンクで確認すると利用者ができてログインできるメールアドレスになり、同じリンクの2回目は ALREADY_VERIFIED に
// なることを確かめる(要件1.2)。
func TestRegister_ThenVerifyEmail(t *testing.T) {
	s, client, mailer := newEmailVerificationService(t, completionNow, nil)
	email, r := registerOne(t, s)

	if r.Email != email || r.Username != "山田<&>太郎" || !r.CreatedAt.Equal(completionNow) {
		t.Errorf("登録の途中の記録 = %+v", r)
	}
	if !strings.HasPrefix(r.PasswordHash, "$2a$10$") || bcrypt.CompareHashAndPassword([]byte(r.PasswordHash), []byte(registerPhrase)) != nil {
		t.Errorf("ハッシュ %q が、強さ10の $2a$ のパスワードのハッシュでない", r.PasswordHash)
	}
	assertTTL(t, client, registrationKeyPrefix+r.ID.String(), 24*time.Hour)
	if len(mailer.got) != 1 || mailer.got[0].Destination.ToAddresses[0] != email {
		t.Fatalf("送ったメール = %d 通, want 登録したメールアドレスへ1通", len(mailer.got))
	}
	token := mailedToken(t, mailer, 0)
	claims, ok := s.readEmailVerificationToken(token)
	if !ok || claims.SubjectID != r.ID || claims.Purpose != purposeRegistration || claims.Email != email {
		t.Fatalf("リンクの項目 = %+v, %v, want 登録の途中の記録 %s の REGISTRATION", claims, ok, r.ID)
	}

	got, err := s.VerifyEmail(t.Context(), token)
	if err != nil || got != (VerifyEmailResult{Result: "VERIFIED"}) {
		t.Fatalf("VerifyEmail = %+v, %v, want VERIFIED", got, err)
	}
	a, found, err := s.findAccountByEmail(t.Context(), email)
	if err != nil || !found || a.ID != r.ID || !a.EmailVerified {
		t.Fatalf("利用者 = %+v, %v, %v, want 確認済みの利用者 %s", a, found, err, r.ID)
	}
	if match, err := passwordMatches(registerPhrase, a.PasswordHash); err != nil || !match {
		t.Errorf("登録したパスワードが合わない: %v, %v", match, err)
	}
	wantPending(t, s, r.ID, false)

	got, err = s.VerifyEmail(t.Context(), token)
	if err != nil || got != (VerifyEmailResult{Result: "ALREADY_VERIFIED"}) {
		t.Errorf("2回目の VerifyEmail = %+v, %v, want ALREADY_VERIFIED", got, err)
	}
}

// TestRegister_Rejections は、Java 版の UserRegistrationUseCase と同じく、すでにある利用者のメールアドレスは、
// メールアドレスの形が正しくなくても 400 の「このメールアドレスは登録できません。」で断り、形が正しくなければ入力の誤りで
// 断ることと、どちらも記録を置かずメールを送らないことを確かめる。
func TestRegister_Rejections(t *testing.T) {
	cases := []struct {
		name     string
		email    string
		existing bool
		check    func(t *testing.T, err error)
	}{
		{"すでにある利用者のメールアドレス", uniqueEmail(), true, func(t *testing.T, err error) {
			wantStatusError(t, err, 400, MessageEmailNotRegistrable, "")
		}},
		{"すでにある利用者の、形の正しくないメールアドレス", "dup-" + uuid.NewString() + "@example.invalidtld", true, func(t *testing.T, err error) {
			wantStatusError(t, err, 400, MessageEmailNotRegistrable, "")
		}},
		{"知らないトップレベルドメイン", "new-" + uuid.NewString() + "@example.invalidtld", false, func(t *testing.T, err error) {
			wantInputError(t, err, "メールアドレスの形式が不正です。")
		}},
		{"ローカルの名前", "new-" + uuid.NewString() + "@localhost", false, func(t *testing.T, err error) {
			wantInputError(t, err, "メールアドレスの形式が不正です。")
		}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			s, _, mailer := newEmailVerificationService(t, completionNow, nil)
			if c.existing {
				insertAccount(t, testAccount{email: c.email, hash: hashOf(t, registerPhrase), version: -1})
			}
			err := s.Register(t.Context(), RegisterInput{Email: c.email, Username: "taro", Password: registerPhrase})
			c.check(t, err)
			wantNoPending(t, s, c.email)
			if len(mailer.got) != 0 {
				t.Errorf("送ったメール = %d 通, want 0通", len(mailer.got))
			}
		})
	}
}

// TestRegister_MailFailureRemovesPending は、確認のメールを送れなければ、置いた登録の途中の記録を消して、
// メールの誤りを返すことを確かめる。
func TestRegister_MailFailureRemovesPending(t *testing.T) {
	s, client, mailer := newEmailVerificationService(t, completionNow, nil)
	mailErr := errors.New("SES が断った")
	mailer.err = mailErr
	email := uniqueEmail()
	err := s.Register(t.Context(), RegisterInput{Email: email, Username: "taro", Password: registerPhrase})
	if !errors.Is(err, mailErr) {
		t.Fatalf("Register = %v, want メールの誤り", err)
	}
	if len(mailer.got) != 1 {
		t.Errorf("SendEmail の呼び出し = %d 回, want 1回", len(mailer.got))
	}
	wantNoPending(t, s, email)
	if keyExists(t, client, registrationEmailKeyPrefix+email) {
		t.Error("メールアドレスごとの集合が残った")
	}
}

// TestRegister_RateLimitedStillAccepted は、Java 版の UserRegistrationUseCase と同じく、送り直せる間隔の中で確認のメールを
// 送れなくても、登録を受け付け、置いた登録の途中の記録を消さずに24時間残すことを確かめる。
func TestRegister_RateLimitedStillAccepted(t *testing.T) {
	s, client, mailer := newEmailVerificationService(t, completionNow, nil)
	email, first := registerOne(t, s)
	if err := s.Register(t.Context(), RegisterInput{Email: email, Username: "taro", Password: registerPhrase}); err != nil {
		t.Fatalf("送り直せる間隔の中の Register = %v, want nil", err)
	}
	pending, err := s.findPendingRegistrationsByEmail(t.Context(), email, maxPendingRegistrations)
	if err != nil || len(pending) != 2 {
		t.Fatalf("登録の途中の記録 = %d 個, %v, want 2個", len(pending), err)
	}
	second := pending[0]
	if second.ID == first.ID {
		second = pending[1]
	}
	if second.ID == first.ID || second.Username != "taro" {
		t.Errorf("2回目の記録 = %+v, want 1回目と別の、利用者名 taro の記録", second)
	}
	assertTTL(t, client, registrationKeyPrefix+second.ID.String(), 24*time.Hour)
	if len(mailer.got) != 1 {
		t.Errorf("送ったメール = %d 通, want 1通", len(mailer.got))
	}
}

// TestVerifyEmail_InvalidToken は、読めないリンクの値は、誤りでなく INVALID になることを確かめる。
func TestVerifyEmail_InvalidToken(t *testing.T) {
	s, _, _ := newEmailVerificationService(t, completionNow, nil)
	for _, token := range []string{"", "not-a-token", "a.b.c"} {
		got, err := s.VerifyEmail(t.Context(), token)
		if err != nil || got != (VerifyEmailResult{Result: "INVALID"}) {
			t.Errorf("VerifyEmail(%q) = %+v, %v, want INVALID", token, got, err)
		}
	}
}

// TestVerifyEmail_PasswordResetReady は、目的が PASSWORD_RESET のリンクを使うと、メールアドレスを確認済みにし、
// リンクの残りの時間だけ再設定の値を置き、結果 PASSWORD_RESET_READY と再設定の値を返すことを確かめる。
func TestVerifyEmail_PasswordResetReady(t *testing.T) {
	s, client, mailer := newEmailVerificationService(t, completionNow, nil)
	email := uniqueEmail()
	id := insertAccount(t, testAccount{email: email, hash: hashOf(t, registerPhrase), version: -1})
	mustSend(t, s, email, id, purposePasswordReset)
	token := mailedToken(t, mailer, 0)

	// 送ってから4分たって使う。残りは6分である
	later, _, _ := newEmailVerificationService(t, completionNow.Add(4*time.Minute), fixedRandom(make([]byte, 32)))
	got, err := later.VerifyEmail(t.Context(), token)
	resetToken, _ := randomToken(fixedRandom(make([]byte, 32)))
	if err != nil || got != (VerifyEmailResult{Result: "PASSWORD_RESET_READY", PasswordResetToken: resetToken}) {
		t.Fatalf("VerifyEmail = %+v, %v, want PASSWORD_RESET_READY と再設定の値 %s", got, err, resetToken)
	}
	userID, found, err := s.findPasswordResetUserID(t.Context(), resetToken)
	if err != nil || !found || userID != id {
		t.Errorf("再設定の値の利用者 = %v, %v, %v, want %s", userID, found, err, id)
	}
	assertTTL(t, client, passwordResetKeyPrefix+resetToken, 6*time.Minute)
	if a, _, err := s.findAccountByEmail(t.Context(), email); err != nil || !a.EmailVerified {
		t.Errorf("利用者 = %+v, %v, want 確認済み", a, err)
	}
	_ = client.Del(t.Context(), passwordResetKeyPrefix+resetToken)

	got, err = later.VerifyEmail(t.Context(), token)
	if err != nil || got != (VerifyEmailResult{Result: "ALREADY_VERIFIED"}) {
		t.Errorf("2回目の VerifyEmail = %+v, %v, want ALREADY_VERIFIED", got, err)
	}
}

// TestVerifyEmail_PasswordResetUnderOneMillisecond は、リンクの残りが1ミリ秒より短いとき、Java 版が Redis に
// 断られて 500 になるのと同じく、再設定の値を置かずに誤りを返すことを確かめる。
func TestVerifyEmail_PasswordResetUnderOneMillisecond(t *testing.T) {
	s, client, mailer := newEmailVerificationService(t, completionNow, nil)
	email := uniqueEmail()
	id := insertAccount(t, testAccount{email: email, hash: hashOf(t, registerPhrase), version: -1})
	mustSend(t, s, email, id, purposePasswordReset)
	token := mailedToken(t, mailer, 0)
	claims, _ := s.readEmailVerificationToken(token)

	last, _, _ := newEmailVerificationService(t, claims.LinkExpiresAt.Add(-999*time.Microsecond), fixedRandom(make([]byte, 32)))
	got, err := last.VerifyEmail(t.Context(), token)
	if err == nil {
		t.Fatalf("VerifyEmail = %+v, nil, want 誤り", got)
	}
	resetToken, _ := randomToken(fixedRandom(make([]byte, 32)))
	if keyExists(t, client, passwordResetKeyPrefix+resetToken) {
		t.Error("再設定の値が置かれた")
	}
}

// TestResend_OldLinkInvalid は、送り直すと、前のリンクは EXPIRED になって使えず、新しいリンクで確認できることを
// 確かめる(要件3.3)。
func TestResend_OldLinkInvalid(t *testing.T) {
	s, client, mailer := newEmailVerificationService(t, completionNow, nil)
	email, r := registerOne(t, s)
	oldToken := mailedToken(t, mailer, 0)
	releaseRate(t, client, email)
	if err := s.ResendEmailVerificationForLogin(t.Context(), email, registerPhrase); err != nil {
		t.Fatalf("ResendEmailVerificationForLogin: %v", err)
	}
	newToken := mailedToken(t, mailer, 1)

	got, err := s.VerifyEmail(t.Context(), oldToken)
	if err != nil || got != (VerifyEmailResult{Result: "EXPIRED"}) {
		t.Errorf("前のリンクの VerifyEmail = %+v, %v, want EXPIRED", got, err)
	}
	if _, found, _ := s.findAccountByEmail(t.Context(), email); found {
		t.Error("前のリンクで利用者ができた")
	}
	got, err = s.VerifyEmail(t.Context(), newToken)
	if err != nil || got != (VerifyEmailResult{Result: "VERIFIED"}) {
		t.Errorf("新しいリンクの VerifyEmail = %+v, %v, want VERIFIED", got, err)
	}
	wantPending(t, s, r.ID, false)
}

// TestResend_RateLimited は、送り直せる間隔の中では、リンクからの送り直しも、ログインの画面からの送り直しも、
// 400 の MessageResendRateLimited で断り、メールを送らないことを確かめる(要件3.4)。
func TestResend_RateLimited(t *testing.T) {
	s, _, mailer := newEmailVerificationService(t, completionNow, nil)
	email, _ := registerOne(t, s)
	token := mailedToken(t, mailer, 0)
	later, _, laterMailer := newEmailVerificationService(t, completionNow.Add(25*time.Hour), nil)

	wantStatusError(t, later.ResendEmailVerification(t.Context(), token), 400, MessageResendRateLimited, "")
	wantStatusError(t, s.ResendEmailVerificationForLogin(t.Context(), email, registerPhrase), 400, MessageResendRateLimited, "")

	accountEmail := uniqueEmail()
	insertAccount(t, testAccount{email: accountEmail, hash: hashOf(t, registerPhrase), version: -1})
	if err := s.ResendEmailVerificationForLogin(t.Context(), accountEmail, registerPhrase); err != nil {
		t.Fatalf("1回目の送り直し: %v", err)
	}
	wantStatusError(t, s.ResendEmailVerificationForLogin(t.Context(), accountEmail, registerPhrase), 400, MessageResendRateLimited, "")
	if len(mailer.got) != 2 || len(laterMailer.got) != 0 {
		t.Errorf("送ったメール = %d 通と %d 通, want 2通と0通", len(mailer.got), len(laterMailer.got))
	}
}

// TestResend_ExpiredLink は、期限の切れたリンクから送り直すと、リンクと同じ宛先と目的で送り、目的が REGISTRATION なら
// 登録の途中の記録を24時間に延ばし、ほかの目的なら延ばさないことを確かめる。
func TestResend_ExpiredLink(t *testing.T) {
	t.Run("REGISTRATION", func(t *testing.T) {
		s, client, mailer := newEmailVerificationService(t, completionNow, nil)
		email, r := registerOne(t, s)
		token := mailedToken(t, mailer, 0)
		releaseRate(t, client, email)
		if err := client.Expire(t.Context(), registrationKeyPrefix+r.ID.String(), time.Hour).Err(); err != nil {
			t.Fatal(err)
		}
		later, _, laterMailer := newEmailVerificationService(t, completionNow.Add(25*time.Hour), nil)
		if err := later.ResendEmailVerification(t.Context(), token); err != nil {
			t.Fatalf("ResendEmailVerification: %v", err)
		}
		claims, ok := later.readEmailVerificationToken(mailedToken(t, laterMailer, 0))
		if !ok || claims.SubjectID != r.ID || claims.Purpose != purposeRegistration || claims.Email != email {
			t.Errorf("送り直したリンクの項目 = %+v, %v", claims, ok)
		}
		assertTTL(t, client, registrationKeyPrefix+r.ID.String(), 24*time.Hour)
	})
	t.Run("ACCOUNT_EMAIL", func(t *testing.T) {
		s, client, mailer := newEmailVerificationService(t, completionNow, nil)
		email := uniqueEmail()
		id := insertAccount(t, testAccount{email: email, hash: hashOf(t, registerPhrase), version: -1})
		mustSend(t, s, email, id, purposeAccountEmail)
		token := mailedToken(t, mailer, 0)
		releaseRate(t, client, email)
		later, _, laterMailer := newEmailVerificationService(t, completionNow.Add(25*time.Hour), nil)
		if err := later.ResendEmailVerification(t.Context(), token); err != nil {
			t.Fatalf("ResendEmailVerification: %v", err)
		}
		claims, ok := later.readEmailVerificationToken(mailedToken(t, laterMailer, 0))
		if !ok || claims.SubjectID != id || claims.Purpose != purposeAccountEmail || claims.Email != email {
			t.Errorf("送り直したリンクの項目 = %+v, %v", claims, ok)
		}
		if keyExists(t, client, registrationKeyPrefix+id.String()) {
			t.Error("登録の途中の記録が置かれた")
		}
	})
}

// TestResend_NotResendable は、読めないリンクと、期限の切れていない今のリンクと、確認の済んだリンクと、
// 登録の途中の記録が無くなったリンクからは送り直さず、400 の MessageNotResendable で断ることを確かめる。
func TestResend_NotResendable(t *testing.T) {
	s, client, mailer := newEmailVerificationService(t, completionNow, nil)
	email, r := registerOne(t, s)
	usable := mailedToken(t, mailer, 0)
	releaseRate(t, client, email)

	verifiedEmail, _ := registerOne(t, s)
	verified := mailedToken(t, mailer, 1)
	if got, err := s.VerifyEmail(t.Context(), verified); err != nil || got.Result != "VERIFIED" {
		t.Fatalf("VerifyEmail = %+v, %v", got, err)
	}
	releaseRate(t, client, verifiedEmail)

	goneEmail, gone := registerOne(t, s)
	goneToken := mailedToken(t, mailer, 3)
	if err := s.deletePendingRegistration(t.Context(), gone); err != nil {
		t.Fatal(err)
	}
	releaseRate(t, client, goneEmail)

	// 記録が無くなったリンクは、期限が切れたあとに送り直しを求める(期限の前は今のリンクとして使える分類になる)
	later, _, laterMailer := newEmailVerificationService(t, completionNow.Add(25*time.Hour), nil)
	before := len(mailer.got)
	cases := []struct {
		name  string
		s     *Service
		token string
	}{
		{"読めない", s, "not-a-token"},
		{"今のリンク", s, usable},
		{"確認済み", s, verified},
		{"記録が無い", later, goneToken},
	}
	for _, c := range cases {
		wantStatusError(t, c.s.ResendEmailVerification(t.Context(), c.token), 400, MessageNotResendable, "")
		if len(mailer.got) != before || len(laterMailer.got) != 0 {
			t.Errorf("%s のリンクでメールを送った", c.name)
		}
	}
	wantPending(t, s, r.ID, true)
}

// TestResend_MailFailure は、リンクからの送り直しでメールを送れなければ、メールの誤りを返し、登録の途中の記録を
// 延ばさないことを確かめる。
func TestResend_MailFailure(t *testing.T) {
	s, client, mailer := newEmailVerificationService(t, completionNow, nil)
	email, r := registerOne(t, s)
	token := mailedToken(t, mailer, 0)
	releaseRate(t, client, email)
	if err := client.Expire(t.Context(), registrationKeyPrefix+r.ID.String(), time.Hour).Err(); err != nil {
		t.Fatal(err)
	}
	later, _, laterMailer := newEmailVerificationService(t, completionNow.Add(25*time.Hour), nil)
	mailErr := errors.New("SES が断った")
	laterMailer.err = mailErr
	if err := later.ResendEmailVerification(t.Context(), token); !errors.Is(err, mailErr) {
		t.Fatalf("ResendEmailVerification = %v, want メールの誤り", err)
	}
	assertTTL(t, client, registrationKeyPrefix+r.ID.String(), time.Hour)

	laterMailer.err = nil
	mailer.err = mailErr
	if err := s.ResendEmailVerificationForLogin(t.Context(), email, registerPhrase); !errors.Is(err, mailErr) {
		t.Fatalf("ResendEmailVerificationForLogin = %v, want メールの誤り", err)
	}
	assertTTL(t, client, registrationKeyPrefix+r.ID.String(), time.Hour)
}

// TestResend_ForLoginAccount は、ログインの画面からの送り直しで、利用者が居れば、パスワードが合い、確認が済んでいない
// ときだけ、目的 ACCOUNT_EMAIL のリンクを送り、ほかは「メールアドレスまたはパスワードが正しくありません。」で断ることを
// 確かめる。
func TestResend_ForLoginAccount(t *testing.T) {
	s, _, mailer := newEmailVerificationService(t, completionNow, nil)

	email := uniqueEmail()
	id := insertAccount(t, testAccount{email: email, hash: hashOf(t, registerPhrase), version: -1})
	if err := s.ResendEmailVerificationForLogin(t.Context(), email, registerPhrase); err != nil {
		t.Fatalf("ResendEmailVerificationForLogin: %v", err)
	}
	claims, ok := s.readEmailVerificationToken(mailedToken(t, mailer, 0))
	if !ok || claims.SubjectID != id || claims.Purpose != purposeAccountEmail || claims.Email != email {
		t.Errorf("リンクの項目 = %+v, %v, want 利用者 %s の ACCOUNT_EMAIL", claims, ok, id)
	}

	rejected := []struct {
		name    string
		account testAccount
		phrase  string
	}{
		{"パスワードが違う", testAccount{hash: hashOf(t, registerPhrase)}, "Wrong0Pass!"},
		{"確認済み", testAccount{hash: hashOf(t, registerPhrase), verified: true}, registerPhrase},
		{"パスワードが無い", testAccount{}, registerPhrase},
	}
	for _, c := range rejected {
		t.Run(c.name, func(t *testing.T) {
			c.account.email = uniqueEmail()
			c.account.version = -1
			insertAccount(t, c.account)
			before := len(mailer.got)
			wantStatusError(t, s.ResendEmailVerificationForLogin(t.Context(), c.account.email, c.phrase), 400, MessageLoginFailed, "")
			if len(mailer.got) != before {
				t.Error("メールを送った")
			}
		})
	}
}

// TestResend_ForLoginPendingRegistration は、ログインの画面からの送り直しで、利用者が居なければ、パスワードが合う
// 登録の途中の記録に目的 REGISTRATION のリンクを送って記録を24時間に延ばし、合う記録が無ければ
// 「メールアドレスまたはパスワードが正しくありません。」で断ることを確かめる。
func TestResend_ForLoginPendingRegistration(t *testing.T) {
	s, client, mailer := newEmailVerificationService(t, completionNow, nil)
	email := uniqueEmail()
	other := pendingRegistration{ID: uuid.New(), Email: email, PasswordHash: deref(hashOf(t, "Other0Pass!")), Username: "a", CreatedAt: completionNow}
	match := pendingRegistration{ID: uuid.New(), Email: email, PasswordHash: deref(hashOf(t, registerPhrase)), Username: "b", CreatedAt: completionNow.Add(-time.Minute)}
	for _, r := range []pendingRegistration{match, other} {
		if err := s.savePendingRegistration(t.Context(), r, time.Hour); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.ResendEmailVerificationForLogin(t.Context(), email, registerPhrase); err != nil {
		t.Fatalf("ResendEmailVerificationForLogin: %v", err)
	}
	claims, ok := s.readEmailVerificationToken(mailedToken(t, mailer, 0))
	if !ok || claims.SubjectID != match.ID || claims.Purpose != purposeRegistration || claims.Email != email {
		t.Errorf("リンクの項目 = %+v, %v, want 登録の途中の記録 %s の REGISTRATION", claims, ok, match.ID)
	}
	assertTTL(t, client, registrationKeyPrefix+match.ID.String(), 24*time.Hour)
	assertTTL(t, client, registrationKeyPrefix+other.ID.String(), time.Hour)

	releaseRate(t, client, email)
	wantStatusError(t, s.ResendEmailVerificationForLogin(t.Context(), email, "Wrong0Pass!"), 400, MessageLoginFailed, "")
	wantStatusError(t, s.ResendEmailVerificationForLogin(t.Context(), uniqueEmail(), registerPhrase), 400, MessageLoginFailed, "")
	if len(mailer.got) != 1 {
		t.Errorf("送ったメール = %d 通, want 1通", len(mailer.got))
	}
}

// TestResend_ForLoginPicksNewestMatch は、登録を2回受け付けると記録が2つでき、ログインの画面からの
// 送り直しは、新しい順に照らして最初にパスワードが合った記録だけに送ることを確かめる。
func TestResend_ForLoginPicksNewestMatch(t *testing.T) {
	s, client, mailer := newEmailVerificationService(t, completionNow, nil)
	email := uniqueEmail()
	for _, phrase := range []string{registerPhrase, registerPhrase} {
		if err := s.Register(t.Context(), RegisterInput{Email: email, Username: "taro", Password: phrase}); err != nil {
			t.Fatalf("Register: %v", err)
		}
		releaseRate(t, client, email)
	}
	pending, err := s.findPendingRegistrationsByEmail(t.Context(), email, maxPendingRegistrations)
	if err != nil || len(pending) != 2 {
		t.Fatalf("登録の途中の記録 = %d 個, %v, want 2個", len(pending), err)
	}
	if err := s.ResendEmailVerificationForLogin(t.Context(), email, registerPhrase); err != nil {
		t.Fatalf("ResendEmailVerificationForLogin: %v", err)
	}
	claims, _ := s.readEmailVerificationToken(mailedToken(t, mailer, 2))
	if claims.SubjectID != pending[0].ID {
		t.Errorf("送った相手 = %s, want 新しい順の最初 %s", claims.SubjectID, pending[0].ID)
	}
}
