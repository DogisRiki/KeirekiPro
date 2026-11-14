package users

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// changedPhrase は、パスワードのテストで新しく設定する文字列である。
const changedPhrase = "N3wPhrase456"

// wrongPhrase は、利用者のパスワードと合わない文字列である。
const wrongPhrase = "Wr0ngPhrase789"

// Java 版の Email.create の文言である。期待の値は、処理の側の定数に頼らずに書く。
const (
	emailBlankMessage   = "メールアドレスが空です。"
	emailInvalidMessage = "メールアドレスの形式が不正です。"
)

// wantPhrase は、利用者 id の行のパスワードのハッシュが、phrase と合うかが want かを確かめる。
func wantPhrase(t *testing.T, id uuid.UUID, phrase string, want bool) {
	t.Helper()
	ok, err := auth.PasswordMatches(phrase, loadUser(t, id).Row.Password)
	if err != nil {
		t.Fatal(err)
	}
	if ok != want {
		t.Errorf("パスワード %q と合う = %v、期待 = %v", phrase, ok, want)
	}
}

// wantUserGone は、err が、文言「不正なアクセスです。」と Cookie を消す印を持つ 401 の誤りかを確かめる。
func wantUserGone(t *testing.T, err error) {
	t.Helper()
	var e *auth.Error
	if !errors.As(err, &e) {
		t.Fatalf("誤り = %v、期待 = 401 の誤り", err)
	}
	if e.Status != 401 || e.Message != "不正なアクセスです。" || len(e.Errors) != 0 || !e.ClearSession {
		t.Errorf("誤り = %d %q %v Cookie を消す=%v、期待 = 401 不正なアクセスです。 {} Cookie を消す", e.Status, e.Message, e.Errors, e.ClearSession)
	}
}

// wantPhraseChanged は、利用者 id の行が、before からパスワードと updated_at と設定待ちのメールアドレス pending だけを変え、
// パスワードが changedPhrase の強さ10のハッシュになったかを確かめる。
func wantPhraseChanged(t *testing.T, id uuid.UUID, before auth.StoredUser, pending pgtype.Text) {
	t.Helper()
	after := loadUser(t, id)
	if !strings.HasPrefix(after.Row.Password.String, "$2a$10$") {
		t.Errorf("パスワードのハッシュ = %q、期待 = $2a$10$ で始まる", after.Row.Password.String)
	}
	wantPhrase(t, id, changedPhrase, true)
	want := before
	want.Row.Password = after.Row.Password
	want.Row.UpdatedAt = javaWallClock(testNow)
	want.Row.PendingEmail = pending
	if !reflect.DeepEqual(after, want) {
		t.Errorf("変えたあとの行\n 得た: %+v\n 期待: %+v", after, want)
	}
}

// phraseOnlyUser は、パスワード deleteTestPassword と GitHub の連携を持ち、メールアドレスを持たない利用者を作る。
func phraseOnlyUser(t *testing.T) uuid.UUID {
	t.Helper()
	hash, err := auth.HashPassword(deleteTestPassword)
	if err != nil {
		t.Fatal(err)
	}
	return insertUser(t, userRow{Password: someText(hash)}, "github")
}

// googleOnlyUser は、Google の連携だけを持ち、メールアドレスとパスワードを持たない利用者を作る。
func googleOnlyUser(t *testing.T) uuid.UUID {
	t.Helper()
	return insertUser(t, userRow{}, "google")
}

func TestChangePassword_WrongNowPassword(t *testing.T) {
	env := newDeleteEnv(t, nil)
	tests := []struct {
		name      string
		noPhrase  bool
		now, next string
		want      map[string][]string
	}{
		{"今のパスワードが合わない", false, wrongPhrase, changedPhrase, map[string][]string{"nowPassword": {MessageNowPhraseWrong}}},
		{"新しいパスワードが今のパスワードと同じ", false, deleteTestPassword, deleteTestPassword, map[string][]string{"newPassword": {MessageNewPhraseSameAsNow}}},
		{"両方の誤りを一緒に返す", false, wrongPhrase, deleteTestPassword, map[string][]string{"nowPassword": {MessageNowPhraseWrong}, "newPassword": {MessageNewPhraseSameAsNow}}},
		{"パスワードの無い利用者では、どちらの照合も合わない", true, deleteTestPassword, deleteTestPassword, map[string][]string{"nowPassword": {MessageNowPhraseWrong}}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			id := verifiedUser(t)
			if tt.noPhrase {
				id = googleOnlyUser(t)
			}
			var sessions []auth.SessionTokens
			if !tt.noPhrase {
				sessions = append(sessions, login(t, env, id))
			}
			before := loadUser(t, id)

			wantInputErrors(t, env.users.ChangePassword(t.Context(), id, tt.now, tt.next), tt.want)

			wantUnchanged(t, id, before)
			// 断ったときは、ログインの状態を使えなくしない
			for _, s := range sessions {
				if _, err := env.auth.VerifyAccessToken(t.Context(), s.AccessToken); err != nil {
					t.Errorf("断ったのにログインの状態の値を使えない: %v", err)
				}
				if n := redisKeys(t, env, sessionKeys(id, s)...); n != 2 {
					t.Errorf("断ったのにログインを続けるための値が消えた: 残り %d 個、期待 = 2 個", n)
				}
			}
		})
	}
}

func TestChangePassword_InvalidatesSessions(t *testing.T) {
	env := newDeleteEnv(t, nil)
	id := verifiedUser(t)
	insertTokenVersion(t, env, id, 0)
	sessions := []auth.SessionTokens{login(t, env, id), login(t, env, id)}
	before := loadUser(t, id)

	if err := env.users.ChangePassword(t.Context(), id, deleteTestPassword, changedPhrase); err != nil {
		t.Fatalf("ChangePassword: %v", err)
	}

	wantPhraseChanged(t, id, before, before.Row.PendingEmail)
	wantPhrase(t, id, deleteTestPassword, false)
	for i, s := range sessions {
		if _, err := env.auth.VerifyAccessToken(t.Context(), s.AccessToken); !errors.Is(err, auth.ErrInvalidToken) {
			t.Errorf("端末 %d のログインの状態の値の誤り = %v、期待 = %v", i, err, auth.ErrInvalidToken)
		}
		_, err := env.auth.Refresh(t.Context(), s.RefreshToken)
		var e *auth.Error
		if !errors.As(err, &e) || e.Status != 401 {
			t.Errorf("端末 %d のログインを続けるための値の誤り = %v、期待 = 401", i, err)
		}
	}
	if n := redisKeys(t, env, sessionKeys(id, sessions...)...); n != 0 {
		t.Errorf("ログインを続けるための値 = %d 個、期待 = 0 個", n)
	}
	// 新しいパスワードでは、ログインでき、その値は使える
	r, err := env.auth.Login(t.Context(), before.Row.Email.String, changedPhrase)
	if err != nil {
		t.Fatalf("新しいパスワードでログインできません: %v", err)
	}
	if _, err := env.auth.VerifyAccessToken(t.Context(), r.Session.AccessToken); err != nil {
		t.Errorf("変えたあとのログインの状態の値を使えない: %v", err)
	}
}

func TestChangePassword_UserGone(t *testing.T) {
	env := newDeleteEnv(t, nil)
	wantUserGone(t, env.users.ChangePassword(t.Context(), uuid.New(), deleteTestPassword, changedPhrase))
}

// newAddress は、ほかのテストの行と重ならないメールアドレスを作り、テストの終わりに、そのメールアドレスと利用者 id の
// 確認のリンクの記録を消す。
func newAddress(t *testing.T, e verificationEnv, id uuid.UUID) string {
	t.Helper()
	address := uuid.NewString() + "-new@example.com"
	e.forgetRecords(t, id, address)
	return address
}

func TestSetEmailAndPassword_WrongNowPassword(t *testing.T) {
	e := newVerificationEnv(t)
	tests := []struct {
		name    string
		current *string
		email   func(id uuid.UUID) *string
	}{
		{"今のパスワードを送らない", nil, func(uuid.UUID) *string { return nil }},
		{"今のパスワードが合わない", ptr(wrongPhrase), func(id uuid.UUID) *string { return ptr(newAddress(t, e, id)) }},
		// メールアドレスの空の誤りは、今のパスワードの誤りより後で返す
		{"メールアドレスが空でも、今のパスワードの誤りを返す", ptr(wrongPhrase), func(uuid.UUID) *string { return ptr("") }},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e.mailer.got = nil
			id := phraseOnlyUser(t)
			before := loadUser(t, id)

			err := e.users.SetEmailAndPassword(t.Context(), SetEmailAndPasswordInput{UserID: id, Email: tt.email(id), Password: changedPhrase, CurrentPassword: tt.current})

			wantBusinessError(t, err, MessageCurrentPhraseWrong)
			wantUnchanged(t, id, before)
			if len(e.mailer.got) != 0 {
				t.Errorf("断ったのにメールを %d 通送った", len(e.mailer.got))
			}
		})
	}
}

func TestSetEmailAndPassword_CollectsEmailErrors(t *testing.T) {
	e := newVerificationEnv(t)
	tests := []struct {
		name  string
		user  func(t *testing.T) uuid.UUID
		email func(id uuid.UUID) string
		want  []string
	}{
		{"メールアドレスを持つ利用者に空のメールアドレス", verifiedUser, func(uuid.UUID) string { return "" }, []string{emailBlankMessage, MessageEmailAlreadySet}},
		{"メールアドレスを持つ利用者に形の誤ったメールアドレス", verifiedUser, func(uuid.UUID) string { return "not-an-address" }, []string{emailInvalidMessage, MessageEmailAlreadySet}},
		{"メールアドレスを持つ利用者に新しいメールアドレス", verifiedUser, func(id uuid.UUID) string { return newAddress(t, e, id) }, []string{MessageEmailAlreadySet}},
		{"メールアドレスを持たない利用者に空白だけのメールアドレス", phraseOnlyUser, func(uuid.UUID) string { return "  " }, []string{emailBlankMessage}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e.mailer.got = nil
			id := tt.user(t)
			before := loadUser(t, id)

			err := e.users.SetEmailAndPassword(t.Context(), SetEmailAndPasswordInput{UserID: id, Email: ptr(tt.email(id)), Password: changedPhrase, CurrentPassword: ptr(deleteTestPassword)})

			wantInputErrors(t, err, map[string][]string{"email": tt.want})
			wantUnchanged(t, id, before)
			if len(e.mailer.got) != 0 {
				t.Errorf("断ったのにメールを %d 通送った", len(e.mailer.got))
			}
		})
	}
}

func TestSetEmailAndPassword_EmailInUse(t *testing.T) {
	e := newVerificationEnv(t)
	other := verifiedUser(t)
	otherEmail := loadUser(t, other).Row.Email.String
	tests := []struct {
		name    string
		user    func(t *testing.T) uuid.UUID
		email   func(id uuid.UUID) string
		current *string
	}{
		{"ほかの利用者のメールアドレス", googleOnlyUser, func(uuid.UUID) string { return otherEmail }, nil},
		{"自分のメールアドレスも断る", verifiedUser, func(id uuid.UUID) string { return loadUser(t, id).Row.Email.String }, ptr(deleteTestPassword)},
		{"今のパスワードの誤りより先に断る", phraseOnlyUser, func(uuid.UUID) string { return otherEmail }, ptr(wrongPhrase)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e.mailer.got = nil
			id := tt.user(t)
			before := loadUser(t, id)

			err := e.users.SetEmailAndPassword(t.Context(), SetEmailAndPasswordInput{UserID: id, Email: ptr(tt.email(id)), Password: changedPhrase, CurrentPassword: tt.current})

			wantBusinessError(t, err, "このメールアドレスは登録できません。")
			wantUnchanged(t, id, before)
			if len(e.mailer.got) != 0 {
				t.Errorf("断ったのにメールを %d 通送った", len(e.mailer.got))
			}
		})
	}
}

func TestSetEmailAndPassword_SendsPendingEmailVerification(t *testing.T) {
	e := newVerificationEnv(t)

	t.Run("パスワードの無い利用者は、今のパスワードを送らずに設定できる", func(t *testing.T) {
		e.mailer.got = nil
		id := googleOnlyUser(t)
		address := newAddress(t, e, id)
		before := loadUser(t, id)

		if err := e.users.SetEmailAndPassword(t.Context(), SetEmailAndPasswordInput{UserID: id, Email: ptr(address), Password: changedPhrase}); err != nil {
			t.Fatalf("SetEmailAndPassword: %v", err)
		}

		wantPhraseChanged(t, id, before, someText(address))
		if len(e.mailer.got) != 1 {
			t.Fatalf("メールを %d 通送った、期待 = 1 通", len(e.mailer.got))
		}
		e.wantLink(t, 0, linkClaims{Purpose: "PENDING_EMAIL", Email: address, Subject: id.String()})
		if got := e.mailedTo(t, 0); !reflect.DeepEqual(got, []string{address}) {
			t.Errorf("宛先 = %v、期待 = %v", got, []string{address})
		}
	})

	t.Run("パスワードを持つ利用者は、今のパスワードが合えば設定できる", func(t *testing.T) {
		e.mailer.got = nil
		id := phraseOnlyUser(t)
		address := newAddress(t, e, id)
		before := loadUser(t, id)

		if err := e.users.SetEmailAndPassword(t.Context(), SetEmailAndPasswordInput{UserID: id, Email: ptr(address), Password: changedPhrase, CurrentPassword: ptr(deleteTestPassword)}); err != nil {
			t.Fatalf("SetEmailAndPassword: %v", err)
		}

		wantPhraseChanged(t, id, before, someText(address))
		if len(e.mailer.got) != 1 {
			t.Fatalf("メールを %d 通送った、期待 = 1 通", len(e.mailer.got))
		}
		e.wantLink(t, 0, linkClaims{Purpose: "PENDING_EMAIL", Email: address, Subject: id.String()})
	})

	t.Run("メールアドレスを省くと、パスワードだけを変え、メールを送らない", func(t *testing.T) {
		e.mailer.got = nil
		id := verifiedUser(t)
		before := loadUser(t, id)

		if err := e.users.SetEmailAndPassword(t.Context(), SetEmailAndPasswordInput{UserID: id, Password: changedPhrase, CurrentPassword: ptr(deleteTestPassword)}); err != nil {
			t.Fatalf("SetEmailAndPassword: %v", err)
		}

		wantPhraseChanged(t, id, before, before.Row.PendingEmail)
		if len(e.mailer.got) != 0 {
			t.Errorf("メールを %d 通送った、期待 = 0 通", len(e.mailer.got))
		}
	})

	t.Run("送り直せる間隔の中でも誤りにせず、前のリンクを使えなくする", func(t *testing.T) {
		e.mailer.got = nil
		id := googleOnlyUser(t)
		address := newAddress(t, e, id)
		sent, err := e.auth.SendEmailVerification(t.Context(), address, id, auth.PendingEmail)
		if err != nil || !sent {
			t.Fatalf("前のリンクを送れません: 送った=%v 誤り=%v", sent, err)
		}
		before := loadUser(t, id)

		if err := e.users.SetEmailAndPassword(t.Context(), SetEmailAndPasswordInput{UserID: id, Email: ptr(address), Password: changedPhrase}); err != nil {
			t.Fatalf("SetEmailAndPassword: %v", err)
		}

		wantPhraseChanged(t, id, before, someText(address))
		if len(e.mailer.got) != 1 {
			t.Fatalf("メールを %d 通送った、期待 = 前のリンクの 1 通だけ", len(e.mailer.got))
		}
		e.wantVerifyResult(t, e.mailedToken(t, 0), "EXPIRED")
	})
}

func TestSetEmailAndPassword_MailFailureRollsBack(t *testing.T) {
	e := newVerificationEnv(t)
	sesErr := errors.New("SES が断った")
	e.mailer.err = sesErr
	id := googleOnlyUser(t)
	address := newAddress(t, e, id)
	before := loadUser(t, id)

	err := e.users.SetEmailAndPassword(t.Context(), SetEmailAndPasswordInput{UserID: id, Email: ptr(address), Password: changedPhrase})

	if !errors.Is(err, sesErr) {
		t.Fatalf("誤り = %v、期待 = %v を包んだ誤り", err, sesErr)
	}
	var ae *auth.Error
	if errors.As(err, &ae) {
		t.Errorf("誤り = %d %q、期待 = 500 にする誤り", ae.Status, ae.Message)
	}
	wantUnchanged(t, id, before)
}

func TestSetEmailAndPassword_UserGone(t *testing.T) {
	e := newVerificationEnv(t)
	wantUserGone(t, e.users.SetEmailAndPassword(t.Context(), SetEmailAndPasswordInput{UserID: uuid.New(), Email: ptr("gone@example.com"), Password: changedPhrase}))
	if len(e.mailer.got) != 0 {
		t.Errorf("メールを %d 通送った、期待 = 0 通", len(e.mailer.got))
	}
}
