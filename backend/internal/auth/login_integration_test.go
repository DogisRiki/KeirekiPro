package auth

import (
	"crypto/rand"
	"errors"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// javaBcryptSample は、開発環境の Java 版の BCryptPasswordEncoder が javaSamplePhrase から作ったハッシュである。
// Java 版は、登録の途中の記録にこのハッシュを置いてログインを求めると、409 の PENDING_REGISTRATION で答えた。
const (
	javaBcryptSample = "$2a$10$7GThZnQnlSFeXeoLg46eZ.KUwPbEaMbPjxFAByKOZsyrVgR9eLY4q"
	javaSamplePhrase = "Passw0rd!Probe"
)

// testAccount は、テストのデータベースに足す利用者である。
type testAccount struct {
	email     string
	hash      *string
	twoFactor bool
	verified  bool
	roles     []string
	// version が負でなければ、ログインの状態の世代の番号の行も足す。
	version int64
}

// insertAccount は、利用者の行と役割の行を足し、その ID を返す。
func insertAccount(t *testing.T, a testAccount) uuid.UUID {
	t.Helper()
	id := uuid.New()
	ctx := t.Context()
	var verifiedAt *time.Time
	if a.verified {
		v := time.Date(2026, 11, 1, 9, 0, 0, 0, time.UTC)
		verifiedAt = &v
	}
	if _, err := testPool.Exec(ctx,
		`INSERT INTO users (id, email, password, two_factor_auth_enabled, email_verified_at, created_at, updated_at)
		 VALUES ($1::uuid, $2, $3, $4, $5, now(), now())`,
		id.String(), a.email, a.hash, a.twoFactor, verifiedAt); err != nil {
		t.Fatalf("利用者の行を足せない: %v", err)
	}
	for _, role := range a.roles {
		if _, err := testPool.Exec(ctx,
			`INSERT INTO user_roles (user_id, role_id, created_at) SELECT $1::uuid, id, now() FROM roles WHERE name = $2`,
			id.String(), role); err != nil {
			t.Fatalf("役割の行を足せない: %v", err)
		}
	}
	if a.version >= 0 {
		if _, err := testPool.Exec(ctx,
			`INSERT INTO user_token_versions (user_id, token_version, updated_at) VALUES ($1::uuid, $2, TIMESTAMP '2000-01-01 00:00:00')`,
			id.String(), a.version); err != nil {
			t.Fatalf("世代の番号の行を足せない: %v", err)
		}
	}
	return id
}

// hashOf は、phrase の bcrypt のハッシュを、いちばん弱い強さで作る。
func hashOf(t *testing.T, phrase string) *string {
	t.Helper()
	b, err := bcrypt.GenerateFromPassword([]byte(phrase), bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	h := string(b)
	return &h
}

// codeFirstRandom は、はじめて4バイトを求められたときに確認のコード 123456 になる4バイトを返し、
// そのほかは本番と同じ乱数を返す関数である。
func codeFirstRandom() func([]byte) (int, error) {
	first := true
	return func(b []byte) (int, error) {
		if first && len(b) == 4 {
			first = false
			return copy(b, []byte{0x00, 0x01, 0xE2, 0x40}), nil
		}
		return rand.Read(b)
	}
}

// newLoginService は、テストのデータベースと Valkey と偽の SES と、Java 版の開発環境と同じ設定の値を使う Service と、
// Redis に直に読み書きするクライアントと、偽の SES を作る。
func newLoginService(t *testing.T) (*Service, redis.UniversalClient, *fakeSES) {
	t.Helper()
	templates, err := backend.MailTemplates()
	if err != nil {
		t.Fatal(err)
	}
	client := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	t.Cleanup(func() { _ = client.Close() })
	mailer := &fakeSES{}
	return New(Deps{
		Pool:          testPool,
		Redis:         client,
		SES:           mailer,
		App:           javaDevApp(t),
		JWT:           config.JWT{Secret: testSigningKey, AccessTokenValidity: 10 * time.Minute, RefreshTokenValidity: refreshValidity},
		MailTemplates: templates,
		Random:        codeFirstRandom(),
	}), client, mailer
}

// wantSession は、tokens のログインの状態の値とログインを続けるための値が、利用者 id と役割 roles と
// 世代の番号 version を表すことを確かめる。
func wantSession(t *testing.T, s *Service, tokens SessionTokens, id uuid.UUID, roles []string, version int64) {
	t.Helper()
	p, err := s.VerifyAccessToken(t.Context(), tokens.AccessToken)
	if err != nil {
		t.Fatalf("VerifyAccessToken: %v", err)
	}
	if p.UserID != id || !slices.Equal(p.Roles, roles) {
		t.Errorf("ログインの状態の値 = %+v, want 利用者 %s と役割 %v", p, id, roles)
	}
	info, ok, err := s.findRefreshToken(t.Context(), tokens.RefreshToken)
	if err != nil || !ok {
		t.Fatalf("findRefreshToken = %v, %v", ok, err)
	}
	want := refreshTokenInfo{UserID: id, Roles: roles, TokenVersion: version}
	if !reflect.DeepEqual(info, want) {
		t.Errorf("ログインを続けるための値 = %+v, want %+v", info, want)
	}
}

// wantStatusError は、err が、状態の番号 status と文言 message と種類 kind の *Error であることを確かめる。
func wantStatusError(t *testing.T, err error, status int, message string, kind EmailKind) {
	t.Helper()
	var e *Error
	if !errors.As(err, &e) {
		t.Fatalf("誤り = %v, want 状態の番号 %d の *Error", err, status)
	}
	if e.Status != status || e.Message != message || e.Kind != kind || e.Errors == nil || len(e.Errors) != 0 || e.ClearSession {
		t.Errorf("誤り = %+v, want 状態の番号 %d と文言 %q と種類 %q", e, status, message, kind)
	}
}

// TestLogin_Success は、2段階認証の無い利用者が、Java 版の作ったハッシュのパスワードでログインすると、
// 役割 USER を持つログインの状態の値と、今の世代の番号のログインを続けるための値が発行され、
// メールが送られないことを確かめる(要件1.2)。
func TestLogin_Success(t *testing.T) {
	s, _, mailer := newLoginService(t)
	email := uniqueEmail()
	hash := javaBcryptSample
	id := insertAccount(t, testAccount{email: email, hash: &hash, verified: true, roles: []string{"USER"}, version: 3})

	res, err := s.Login(t.Context(), email, javaSamplePhrase)
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	if res.TwoFactorChallenge != "" {
		t.Errorf("途中の記録の値 = %q, want 空", res.TwoFactorChallenge)
	}
	wantSession(t, s, res.Session, id, []string{"USER"}, 3)
	if len(mailer.got) != 0 {
		t.Errorf("メールの送り出し = %d 回, want 0 回", len(mailer.got))
	}

	// 役割の無い利用者は、役割の無い値を受け取る
	email2 := uniqueEmail()
	id2 := insertAccount(t, testAccount{email: email2, hash: &hash, verified: true, version: -1})
	res, err = s.Login(t.Context(), email2, javaSamplePhrase)
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	wantSession(t, s, res.Session, id2, []string{}, 0)
}

// TestVerifyTwoFactor_Success は、2段階認証が有効な利用者のログインが、ログインの状態の値を発行せずに
// 確認のコードのメールを送って途中の記録の値を返し、そのコードの確認が通ると、途中の記録と確認のコードを消して
// ログインの状態の値2つを発行することを確かめる。値の役割は USER、ADMIN の順に並ぶ(要件1.2、3.2)。
func TestVerifyTwoFactor_Success(t *testing.T) {
	s, client, mailer := newLoginService(t)
	email := uniqueEmail()
	id := insertAccount(t, testAccount{email: email, hash: hashOf(t, javaSamplePhrase), twoFactor: true, verified: true, roles: []string{"ADMIN", "USER"}, version: 2})

	res, err := s.Login(t.Context(), email, javaSamplePhrase)
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	if res.TwoFactorChallenge == "" || res.Session != (SessionTokens{}) {
		t.Fatalf("Login の結果 = %+v, want 途中の記録の値だけ", res)
	}
	if len(mailer.got) != 1 || strings.Join(mailer.got[0].Destination.ToAddresses, ",") != email {
		t.Fatalf("メールの送り出し = %+v, want %s に1回", mailer.got, email)
	}
	challengeKey := twoFactorChallengeKeyPrefix + res.TwoFactorChallenge
	codeKey := twoFactorCodeKeyPrefix + id.String()
	if got := rawValue(t, client, codeKey); got != jsonQuoted(t, twoFactorTestCode) {
		t.Fatalf("確認のコード = %s, want %s", got, jsonQuoted(t, twoFactorTestCode))
	}

	tokens, err := s.VerifyTwoFactor(t.Context(), res.TwoFactorChallenge, twoFactorTestCode)
	if err != nil {
		t.Fatalf("VerifyTwoFactor: %v", err)
	}
	wantSession(t, s, tokens, id, []string{"USER", "ADMIN"}, 2)
	for _, key := range []string{challengeKey, codeKey} {
		if keyExists(t, client, key) {
			t.Errorf("%s が残っている", key)
		}
	}

	// 同じ途中の記録の値は、2回目には使えない
	_, err = s.VerifyTwoFactor(t.Context(), res.TwoFactorChallenge, twoFactorTestCode)
	wantBusinessError(t, err, MessageInvalidTwoFactorSession)
}

// TestVerifyTwoFactor_Rejects は、途中の記録の値が空のときと、確認のコードが違うときに断ることと、
// 利用者が居ないときは、途中の記録と確認のコードを消してから MessageUserInfoUnavailable で断ることを確かめる。
func TestVerifyTwoFactor_Rejects(t *testing.T) {
	s, client, _ := newLoginService(t)

	_, err := s.VerifyTwoFactor(t.Context(), "", twoFactorTestCode)
	wantBusinessError(t, err, MessageInvalidTwoFactorSession)

	missing := uuid.New()
	challenge, err := s.issueTwoFactor(t.Context(), missing, "missing@example.com")
	if err != nil {
		t.Fatalf("issueTwoFactor: %v", err)
	}
	_, err = s.VerifyTwoFactor(t.Context(), challenge, "000000")
	wantBusinessError(t, err, MessageInvalidTwoFactorCode)

	_, err = s.VerifyTwoFactor(t.Context(), challenge, twoFactorTestCode)
	wantBusinessError(t, err, MessageUserInfoUnavailable)
	for _, key := range []string{twoFactorChallengeKeyPrefix + challenge, twoFactorCodeKeyPrefix + missing.String()} {
		if keyExists(t, client, key) {
			t.Errorf("%s が残っている", key)
		}
	}
}

// TestLogin_NoAccountAndWrongPasswordSameError は、アカウントが無いときと、パスワードが違うときと、
// パスワードを持たない利用者のときに、同じ誤りで断ることと、確認の済んでいない利用者でも、パスワードが違えば
// 同じ誤りになることを確かめる(要件3.6)。
func TestLogin_NoAccountAndWrongPasswordSameError(t *testing.T) {
	s, _, _ := newLoginService(t)
	verified := uniqueEmail()
	insertAccount(t, testAccount{email: verified, hash: hashOf(t, javaSamplePhrase), verified: true, roles: []string{"USER"}, version: -1})
	unverified := uniqueEmail()
	insertAccount(t, testAccount{email: unverified, hash: hashOf(t, javaSamplePhrase), version: -1})
	oidcOnly := uniqueEmail()
	insertAccount(t, testAccount{email: oidcOnly, verified: true, roles: []string{"USER"}, version: -1})

	var errs []error
	for _, c := range []struct{ email, phrase string }{
		{uniqueEmail(), javaSamplePhrase},
		{verified, javaSamplePhrase + "x"},
		{unverified, javaSamplePhrase + "x"},
		{oidcOnly, javaSamplePhrase},
	} {
		_, err := s.Login(t.Context(), c.email, c.phrase)
		wantBusinessError(t, err, MessageLoginFailed)
		errs = append(errs, err)
	}
	for i := 1; i < len(errs); i++ {
		if !reflect.DeepEqual(errs[0], errs[i]) {
			t.Errorf("誤り %d = %+v, want アカウントが無いときと同じ %+v", i, errs[i], errs[0])
		}
	}
}

// TestLogin_RejectsAccountJavaCannotRead は、Java 版の User.reconstruct が読むときに断る利用者を、Go 版も
// パスワードを照らす前に同じ 400 で断り、ログインの状態の値と確認のコードを発行しないことを確かめる。
// 2段階認証が無効な管理者と、2段階認証が有効でパスワードの無い利用者は、ログインで断る。2段階認証の確認の
// あいだに、2段階認証が無効になった管理者と、メールアドレスが無くなった利用者は、確認で断る。
func TestLogin_RejectsAccountJavaCannotRead(t *testing.T) {
	s, _, mailer := newLoginService(t)
	adminEmail := uniqueEmail()
	insertAccount(t, testAccount{email: adminEmail, hash: hashOf(t, javaSamplePhrase), verified: true, roles: []string{"USER", "ADMIN"}, version: 0})
	noHashEmail := uniqueEmail()
	insertAccount(t, testAccount{email: noHashEmail, twoFactor: true, verified: true, roles: []string{"USER"}, version: 0})
	for _, phrase := range []string{javaSamplePhrase, "wrong"} {
		_, err := s.Login(t.Context(), adminEmail, phrase)
		wantBusinessError(t, err, MessageAdminNeedsTwoFactor)
		_, err = s.Login(t.Context(), noHashEmail, phrase)
		wantBusinessError(t, err, MessageTwoFactorPrerequisiteMissing)
	}
	if len(mailer.got) != 0 {
		t.Errorf("メールの送り出し = %d 回, want 0 回", len(mailer.got))
	}

	tests := []struct {
		name   string
		change string
		want   string
	}{
		{"2段階認証が無効になった管理者", `UPDATE users SET two_factor_auth_enabled = false WHERE id = $1::uuid`, MessageAdminNeedsTwoFactor},
		{"メールアドレスが無くなった利用者", `UPDATE users SET email = NULL WHERE id = $1::uuid`, MessageTwoFactorPrerequisiteMissing},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sub, _, _ := newLoginService(t)
			email := uniqueEmail()
			id := insertAccount(t, testAccount{email: email, hash: hashOf(t, javaSamplePhrase), twoFactor: true, verified: true, roles: []string{"USER", "ADMIN"}, version: 0})
			res, err := sub.Login(t.Context(), email, javaSamplePhrase)
			if err != nil || res.TwoFactorChallenge == "" {
				t.Fatalf("Login = %+v, %v, want 途中の記録の値", res, err)
			}
			if _, err := testPool.Exec(t.Context(), tt.change, id.String()); err != nil {
				t.Fatal(err)
			}
			tokens, err := sub.VerifyTwoFactor(t.Context(), res.TwoFactorChallenge, twoFactorTestCode)
			wantBusinessError(t, err, tt.want)
			if tokens != (SessionTokens{}) {
				t.Errorf("値 = %+v, want 空", tokens)
			}
		})
	}
}

// TestLogin_UnverifiedAccount409 は、メールアドレスの確認が済んでいない利用者は、パスワードが合えば、
// 2段階認証が有効でも確認のコードを送らずに、409 の UNVERIFIED_ACCOUNT_EMAIL で断ることを確かめる。
func TestLogin_UnverifiedAccount409(t *testing.T) {
	s, client, mailer := newLoginService(t)
	email := uniqueEmail()
	id := insertAccount(t, testAccount{email: email, hash: hashOf(t, javaSamplePhrase), twoFactor: true, roles: []string{"USER"}, version: -1})

	_, err := s.Login(t.Context(), email, javaSamplePhrase)
	wantStatusError(t, err, 409, MessageEmailNotVerified, KindUnverifiedAccountEmail)
	if len(mailer.got) != 0 || keyExists(t, client, twoFactorCodeKeyPrefix+id.String()) {
		t.Errorf("確認のコードが送られた: メール %d 回", len(mailer.got))
	}
}

// TestLogin_PendingRegistration409 は、アカウントが無く、登録の途中の記録のどれかのパスワードが合えば、
// 409 の PENDING_REGISTRATION で断り、どれも合わなければアカウントが無いときと同じ誤りにすることと、
// アカウントがあれば登録の途中の記録を照らさないことを確かめる。
func TestLogin_PendingRegistration409(t *testing.T) {
	s, _, _ := newLoginService(t)
	email := uniqueEmail()
	for _, phrase := range []string{"Other1Phrase", javaSamplePhrase} {
		r := sampleRegistration()
		r.ID = uuid.New()
		r.Email = email
		r.PasswordHash = *hashOf(t, phrase)
		if err := s.savePendingRegistration(t.Context(), r, time.Hour); err != nil {
			t.Fatalf("savePendingRegistration: %v", err)
		}
	}

	_, err := s.Login(t.Context(), email, javaSamplePhrase)
	wantStatusError(t, err, 409, MessageEmailNotVerified, KindPendingRegistration)
	_, err = s.Login(t.Context(), email, "Third1Phrase")
	wantBusinessError(t, err, MessageLoginFailed)

	insertAccount(t, testAccount{email: email, hash: hashOf(t, "Account1Phrase"), verified: true, version: -1})
	_, err = s.Login(t.Context(), email, javaSamplePhrase)
	wantBusinessError(t, err, MessageLoginFailed)
}

// TestLogin_PasswordLikeSpring は、パスワードとハッシュの照らし方が、開発環境の Java 版の
// BCryptPasswordEncoder で確かめた結果と同じであることを確かめる。
func TestLogin_PasswordLikeSpring(t *testing.T) {
	body := strings.TrimPrefix(javaBcryptSample, "$2a$10$")
	long72 := strings.Repeat("a", 72)
	h72 := *hashOf(t, long72)
	cases := []struct {
		name, hash, phrase string
		want               bool
	}{
		{"2a", javaBcryptSample, javaSamplePhrase, true},
		{"2b", "$2b$10$" + body, javaSamplePhrase, true},
		{"2y", "$2y$10$" + body, javaSamplePhrase, true},
		{"違うパスワード", javaBcryptSample, javaSamplePhrase + "x", false},
		{"2x", "$2x$10$" + body, javaSamplePhrase, false},
		{"版の文字が無い", "$2$10$" + body, javaSamplePhrase, false},
		{"空", "", javaSamplePhrase, false},
		{"短い", "$2a$10$abc", javaSamplePhrase, false},
		{"末尾に余り", javaBcryptSample + "x", javaSamplePhrase, false},
		{"ハッシュの末尾が正規でない", strings.TrimSuffix(javaBcryptSample, "q") + "r", javaSamplePhrase, false},
		{"塩の末尾が正規でない", "$2a$10$" + body[:21] + "/" + body[22:], javaSamplePhrase, false},
		{"強さが2桁の数でない", "$2a$1x$" + body, javaSamplePhrase, false},
		{"72バイト", h72, long72, true},
		{"73バイトは72バイトに切り詰める", h72, long72 + "b", true},
		{"71バイト", h72, long72[:71], false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := passwordMatches(c.phrase, pgtype.Text{String: c.hash, Valid: true})
			if err != nil || got != c.want {
				t.Errorf("passwordMatches = %v, %v, want %v", got, err, c.want)
			}
		})
	}

	if got, err := passwordMatches(javaSamplePhrase, pgtype.Text{}); err != nil || got {
		t.Errorf("ハッシュが無いとき passwordMatches = %v, %v, want false", got, err)
	}
	// Java 版は、強さが4から31の外のハッシュで例外にし、500 で答える
	for _, cost := range []string{"03", "32"} {
		got, err := passwordMatches(javaSamplePhrase, pgtype.Text{String: "$2a$" + cost + "$" + body, Valid: true})
		var e *Error
		if err == nil || errors.As(err, &e) || got {
			t.Errorf("強さ %s のとき passwordMatches = %v, %v, want 業務の誤りでない誤り", cost, got, err)
		}
	}
}

// TestLogin_HashErrors は、照らせないハッシュのときに、ログインが、業務の誤りでない誤りを返すことを確かめる。
// アカウントのハッシュでも、登録の途中の記録のハッシュでも同じである。
func TestLogin_HashErrors(t *testing.T) {
	s, _, _ := newLoginService(t)
	bad := "$2a$03$" + strings.TrimPrefix(javaBcryptSample, "$2a$10$")
	email := uniqueEmail()
	insertAccount(t, testAccount{email: email, hash: &bad, verified: true, version: -1})
	pendingEmail := uniqueEmail()
	r := sampleRegistration()
	r.ID = uuid.New()
	r.Email = pendingEmail
	r.PasswordHash = bad
	if err := s.savePendingRegistration(t.Context(), r, time.Hour); err != nil {
		t.Fatalf("savePendingRegistration: %v", err)
	}
	for _, e := range []string{email, pendingEmail} {
		_, err := s.Login(t.Context(), e, javaSamplePhrase)
		var authErr *Error
		if err == nil || errors.As(err, &authErr) {
			t.Errorf("%s の Login の誤り = %v, want 業務の誤りでない誤り", e, err)
		}
	}
}

// TestRefresh_Success は、ログインを続けるための値から、値に結び付いた利用者と役割の、
// 今の世代の番号のログインの状態の値が作られることを確かめる(要件3.1)。
func TestRefresh_Success(t *testing.T) {
	s, _, _ := newLoginService(t)
	email := uniqueEmail()
	id := insertAccount(t, testAccount{email: email, hash: hashOf(t, javaSamplePhrase), verified: true, roles: []string{"USER"}, version: 5})
	res, err := s.Login(t.Context(), email, javaSamplePhrase)
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	access, err := s.Refresh(t.Context(), res.Session.RefreshToken)
	if err != nil {
		t.Fatalf("Refresh: %v", err)
	}
	wantSession(t, s, SessionTokens{AccessToken: access, RefreshToken: res.Session.RefreshToken}, id, []string{"USER"}, 5)
}

// TestRefresh_RejectsOldVersion は、ログインを続けるための値の世代の番号が、今の世代の番号と違うときは、
// 値を消してから 401 で断ることと、値が空か見つからないときも 401 で断ることを確かめる(要件3.1)。
func TestRefresh_RejectsOldVersion(t *testing.T) {
	s, client, _ := newLoginService(t)
	email := uniqueEmail()
	id := insertAccount(t, testAccount{email: email, hash: hashOf(t, javaSamplePhrase), verified: true, version: 0})
	res, err := s.Login(t.Context(), email, javaSamplePhrase)
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	if err := s.BumpTokenVersion(t.Context(), sqlcgen.New(testPool), id); err != nil {
		t.Fatalf("BumpTokenVersion: %v", err)
	}

	_, err = s.Refresh(t.Context(), res.Session.RefreshToken)
	wantStatusError(t, err, 401, MessageUnauthenticated, "")
	if keyExists(t, client, refreshTokenKeyPrefix+res.Session.RefreshToken) {
		t.Error("古い世代の値が残っている")
	}
	if got := setMembers(t, client, userRefreshKeyPrefix+id.String()); len(got) != 0 {
		t.Errorf("利用者の集合 = %v, want 空", got)
	}

	for _, value := range []string{"", "unknown-" + uuid.NewString()} {
		_, err = s.Refresh(t.Context(), value)
		wantStatusError(t, err, 401, MessageUnauthenticated, "")
	}
}

// TestLogout_Success は、ログアウトで、ログインを続けるための値が消え、世代の番号が上がって、
// ログインの状態の値が使えなくなることを確かめる(要件1.2)。
func TestLogout_Success(t *testing.T) {
	s, client, _ := newLoginService(t)
	email := uniqueEmail()
	id := insertAccount(t, testAccount{email: email, hash: hashOf(t, javaSamplePhrase), verified: true, version: 0})
	res, err := s.Login(t.Context(), email, javaSamplePhrase)
	if err != nil {
		t.Fatalf("Login: %v", err)
	}

	if err := s.Logout(t.Context(), res.Session.RefreshToken, res.Session.AccessToken); err != nil {
		t.Fatalf("Logout: %v", err)
	}
	if keyExists(t, client, refreshTokenKeyPrefix+res.Session.RefreshToken) {
		t.Error("ログインを続けるための値が残っている")
	}
	if v, _, _ := tokenVersionRow(t, id); v != 1 {
		t.Errorf("世代の番号 = %d, want 1", v)
	}
	if _, err := s.VerifyAccessToken(t.Context(), res.Session.AccessToken); !errors.Is(err, ErrInvalidToken) {
		t.Errorf("VerifyAccessToken の誤り = %v, want ErrInvalidToken", err)
	}
}

// TestLogout_InvalidatesAllSessions は、1つの端末のログアウトで、同じ利用者のほかの端末の
// ログインを続けるための値とログインの状態の値も使えなくなることを確かめる(要件3.5)。
func TestLogout_InvalidatesAllSessions(t *testing.T) {
	s, client, _ := newLoginService(t)
	email := uniqueEmail()
	id := insertAccount(t, testAccount{email: email, hash: hashOf(t, javaSamplePhrase), verified: true, version: 0})
	var sessions []SessionTokens
	for range 2 {
		res, err := s.Login(t.Context(), email, javaSamplePhrase)
		if err != nil {
			t.Fatalf("Login: %v", err)
		}
		sessions = append(sessions, res.Session)
	}

	if err := s.Logout(t.Context(), sessions[0].RefreshToken, sessions[0].AccessToken); err != nil {
		t.Fatalf("Logout: %v", err)
	}
	other := sessions[1]
	if keyExists(t, client, refreshTokenKeyPrefix+other.RefreshToken) || keyExists(t, client, userRefreshKeyPrefix+id.String()) {
		t.Error("ほかの端末のログインを続けるための値が残っている")
	}
	_, err := s.Refresh(t.Context(), other.RefreshToken)
	wantStatusError(t, err, 401, MessageUnauthenticated, "")
	if _, err := s.VerifyAccessToken(t.Context(), other.AccessToken); !errors.Is(err, ErrInvalidToken) {
		t.Errorf("ほかの端末の VerifyAccessToken の誤り = %v, want ErrInvalidToken", err)
	}
}

// TestLogout_IdentifiesUser は、ログインを続けるための値が無いか見つからないときは、ログインの状態の値から
// 利用者を特定することと、どちらからも特定できなければ、何も変えずに終えることを確かめる。
func TestLogout_IdentifiesUser(t *testing.T) {
	s, client, _ := newLoginService(t)
	cases := []struct {
		name         string
		refresh      func(SessionTokens) string
		access       func(SessionTokens) string
		wantVersion  int64
		wantSetEmpty bool
	}{
		{"ログインを続けるための値だけ", func(x SessionTokens) string { return x.RefreshToken }, func(SessionTokens) string { return "" }, 1, true},
		{"ログインの状態の値だけ", func(SessionTokens) string { return "" }, func(x SessionTokens) string { return x.AccessToken }, 1, true},
		{"見つからない値とログインの状態の値", func(SessionTokens) string { return "unknown-" + uuid.NewString() }, func(x SessionTokens) string { return x.AccessToken }, 1, true},
		{"受け付けないログインの状態の値", func(SessionTokens) string { return "" }, func(SessionTokens) string { return "garbage" }, 0, false},
		{"どちらも無い", func(SessionTokens) string { return "" }, func(SessionTokens) string { return "" }, 0, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			email := uniqueEmail()
			id := insertAccount(t, testAccount{email: email, hash: hashOf(t, javaSamplePhrase), verified: true, version: 0})
			res, err := s.Login(t.Context(), email, javaSamplePhrase)
			if err != nil {
				t.Fatalf("Login: %v", err)
			}
			if err := s.Logout(t.Context(), c.refresh(res.Session), c.access(res.Session)); err != nil {
				t.Fatalf("Logout: %v", err)
			}
			if v, _, _ := tokenVersionRow(t, id); v != c.wantVersion {
				t.Errorf("世代の番号 = %d, want %d", v, c.wantVersion)
			}
			if got := len(setMembers(t, client, userRefreshKeyPrefix+id.String())) == 0; got != c.wantSetEmpty {
				t.Errorf("利用者の集合が空 = %v, want %v", got, c.wantSetEmpty)
			}
		})
	}
}

// TestLogin_InfraErrors は、データベースか Redis を使えないときに、4つの操作が、業務の誤りでない誤りを返すことを確かめる。
func TestLogin_InfraErrors(t *testing.T) {
	s, _, _ := newLoginService(t)
	email := uniqueEmail()
	id := insertAccount(t, testAccount{email: email, hash: hashOf(t, javaSamplePhrase), verified: true, version: 0})
	res, err := s.Login(t.Context(), email, javaSamplePhrase)
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	challenge, err := s.issueTwoFactor(t.Context(), id, email)
	if err != nil {
		t.Fatalf("issueTwoFactor: %v", err)
	}

	closedPool, err := pgxpool.New(t.Context(), testPool.Config().ConnString())
	if err != nil {
		t.Fatalf("接続の束を作れない: %v", err)
	}
	closedPool.Close()
	noDB := *s
	noDB.deps.Pool = closedPool
	closedRedis := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	_ = closedRedis.Close()
	noRedis := *s
	noRedis.deps.Redis = closedRedis

	wantInfra := func(name string, err error) {
		t.Helper()
		var e *Error
		if err == nil || errors.As(err, &e) {
			t.Errorf("%s の誤り = %v, want 業務の誤りでない誤り", name, err)
		}
	}
	_, err = noDB.Login(t.Context(), email, javaSamplePhrase)
	wantInfra("データベースの無い Login", err)
	_, err = noRedis.Login(t.Context(), uniqueEmail(), javaSamplePhrase)
	wantInfra("Redis の無い Login", err)
	_, err = noDB.VerifyTwoFactor(t.Context(), challenge, twoFactorTestCode)
	wantInfra("データベースの無い VerifyTwoFactor", err)
	_, err = noRedis.Refresh(t.Context(), res.Session.RefreshToken)
	wantInfra("Redis の無い Refresh", err)
	_, err = noDB.Refresh(t.Context(), res.Session.RefreshToken)
	wantInfra("データベースの無い Refresh", err)
	err = noRedis.Logout(t.Context(), res.Session.RefreshToken, "")
	wantInfra("Redis の無い Logout", err)
	err = noDB.Logout(t.Context(), "", res.Session.AccessToken)
	wantInfra("データベースの無い Logout", err)
	err = noDB.Logout(t.Context(), res.Session.RefreshToken, "")
	wantInfra("データベースの無い Logout の無効化", err)
}
