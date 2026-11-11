package auth

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// uniqueResetToken は、テストごとに違う再設定の値を返す。
func uniqueResetToken() string {
	return "reset-" + uuid.NewString()
}

// mustGetRaw は、キーの値を、Redis に置かれたままの文字列で返す。
func mustGetRaw(t *testing.T, client redis.UniversalClient, key string) string {
	t.Helper()
	got, err := client.Get(t.Context(), key).Result()
	if err != nil {
		t.Fatalf("GET %s: %v", key, err)
	}
	return got
}

// TestPasswordResetToken_TTL10Minutes は、再設定の値の有効な時間が Java 版の RequestPasswordResetUseCase と同じ10分であり、
// 置き場が渡された有効な時間を付けることを確かめる。Java 版の VerifyEmailUseCase は、確認のリンクの残りの時間を渡すので、
// 置き場は有効な時間を決め打ちにしない。
func TestPasswordResetToken_TTL10Minutes(t *testing.T) {
	if passwordResetTokenValidity != 10*time.Minute {
		t.Errorf("再設定の値の有効な時間 = %v, want 10m0s", passwordResetTokenValidity)
	}
	s, client := newRedisService(t)
	for _, ttl := range []time.Duration{passwordResetTokenValidity, 3 * time.Minute} {
		token := uniqueResetToken()
		if err := s.storePasswordResetToken(t.Context(), token, uuid.New(), ttl); err != nil {
			t.Fatalf("storePasswordResetToken(%v): %v", ttl, err)
		}
		assertTTL(t, client, "password-reset:"+token, ttl)
	}
}

// TestPasswordResetToken_ValueIsUserIDJSON は、再設定の値の記録が、Java 版の RedisPasswordResetTokenStore と同じく、
// キー password-reset:<値> に、利用者の ID を JSON の文字列にして置いたものであることを確かめる。
// Go 版が置いた記録を Java 版が読めるように、置いた値がバイトまで同じであることを確かめ、
// Java 版が置いた記録を Go 版が読めるように、同じ形の値を Redis に直に置いて読む。
func TestPasswordResetToken_ValueIsUserIDJSON(t *testing.T) {
	ctx := t.Context()
	s, client := newRedisService(t)

	t.Run("置いた値が利用者の ID の JSON の文字列である", func(t *testing.T) {
		token := uniqueResetToken()
		userID := uuid.New()
		if err := s.storePasswordResetToken(ctx, token, userID, passwordResetTokenValidity); err != nil {
			t.Fatalf("storePasswordResetToken: %v", err)
		}
		if got, want := mustGetRaw(t, client, "password-reset:"+token), `"`+userID.String()+`"`; got != want {
			t.Errorf("置いた値 = %q, want %q", got, want)
		}
		got, ok, err := s.findPasswordResetUserID(ctx, token)
		if err != nil || !ok || got != userID {
			t.Errorf("findPasswordResetUserID = %v, %v, %v, want %v, true, nil", got, ok, err, userID)
		}
	})

	t.Run("Java 版が置いた形の値を読む", func(t *testing.T) {
		token := uniqueResetToken()
		userID := uuid.MustParse("0a0d6b7d-385d-45a0-bdb3-ede0e6f3ea5d")
		if err := client.Set(ctx, "password-reset:"+token, `"0a0d6b7d-385d-45a0-bdb3-ede0e6f3ea5d"`, time.Minute).Err(); err != nil {
			t.Fatal(err)
		}
		got, ok, err := s.findPasswordResetUserID(ctx, token)
		if err != nil || !ok || got != userID {
			t.Errorf("findPasswordResetUserID = %v, %v, %v, want %v, true, nil", got, ok, err, userID)
		}
	})

	t.Run("記録が無い", func(t *testing.T) {
		got, ok, err := s.findPasswordResetUserID(ctx, uniqueResetToken())
		if err != nil || ok || got != uuid.Nil {
			t.Errorf("findPasswordResetUserID = %v, %v, %v, want 無い", got, ok, err)
		}
	})

	t.Run("値が JSON の null", func(t *testing.T) {
		// Java 版の findUserId は、読んだ値が null なら empty を返す
		token := uniqueResetToken()
		if err := client.Set(ctx, "password-reset:"+token, `null`, time.Minute).Err(); err != nil {
			t.Fatal(err)
		}
		got, ok, err := s.findPasswordResetUserID(ctx, token)
		if err != nil || ok || got != uuid.Nil {
			t.Errorf("findPasswordResetUserID = %v, %v, %v, want 無い", got, ok, err)
		}
	})

	t.Run("消す", func(t *testing.T) {
		token := uniqueResetToken()
		if err := s.storePasswordResetToken(ctx, token, uuid.New(), passwordResetTokenValidity); err != nil {
			t.Fatal(err)
		}
		if err := s.removePasswordResetToken(ctx, token); err != nil {
			t.Fatalf("removePasswordResetToken: %v", err)
		}
		if keyExists(t, client, "password-reset:"+token) {
			t.Error("消したあとも記録が残った")
		}
		if _, ok, err := s.findPasswordResetUserID(ctx, token); err != nil || ok {
			t.Errorf("消したあとの findPasswordResetUserID = %v, %v, want 無い", ok, err)
		}
		// Java 版の redisTemplate.delete は、キーが無くても例外にしない
		if err := s.removePasswordResetToken(ctx, token); err != nil {
			t.Errorf("無い記録の removePasswordResetToken: %v", err)
		}
	})

	// Java 版は、値が文字列でないと (String) の型の変換で、UUID でないと UUID.fromString で例外にし、500 で答える
	for _, tc := range []struct {
		name string
		raw  string
	}{
		{name: "値が JSON の数", raw: `123`},
		{name: "値が JSON のオブジェクト", raw: `{"userId":"0a0d6b7d-385d-45a0-bdb3-ede0e6f3ea5d"}`},
		{name: "値が UUID でない文字列", raw: `"not-a-uuid"`},
		{name: "値が空の文字列", raw: `""`},
		{name: "値がハイフンの無い UUID", raw: `"0a0d6b7d385d45a0bdb3ede0e6f3ea5d"`},
		{name: "値が JSON でない", raw: `0a0d6b7d-385d-45a0-bdb3-ede0e6f3ea5d`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			token := uniqueResetToken()
			if err := client.Set(ctx, "password-reset:"+token, tc.raw, time.Minute).Err(); err != nil {
				t.Fatal(err)
			}
			got, ok, err := s.findPasswordResetUserID(ctx, token)
			if err == nil {
				t.Errorf("findPasswordResetUserID = %v, %v, nil, want 誤り", got, ok)
			}
		})
	}
}

// TestPasswordResetToken_Errors は、有効な時間が0以下のときと、Redis を使えないときに、誤りを返すことを確かめる。
func TestPasswordResetToken_Errors(t *testing.T) {
	ctx := t.Context()
	t.Run("有効な時間が0以下", func(t *testing.T) {
		// Java 版の VerifyEmailUseCase は、確認のリンクの残りの時間を渡すので、0以下の時間が届きうる。
		// Java 版は Redis が断って例外になる。Go 版は記録を置かずに誤りを返す
		s, client := newRedisService(t)
		for _, ttl := range []time.Duration{0, -time.Second} {
			token := uniqueResetToken()
			if err := s.storePasswordResetToken(ctx, token, uuid.New(), ttl); err == nil {
				t.Errorf("storePasswordResetToken(%v) が誤りを返さない", ttl)
			}
			if keyExists(t, client, "password-reset:"+token) {
				t.Errorf("有効な時間 %v で記録が置かれた", ttl)
			}
		}
	})
	t.Run("Redis", func(t *testing.T) {
		closed := redisstore.New(redisstore.Options{Addr: testRedisAddr})
		if err := closed.Close(); err != nil {
			t.Fatal(err)
		}
		s := New(Deps{Redis: closed})
		if err := s.storePasswordResetToken(ctx, "v", uuid.New(), passwordResetTokenValidity); err == nil {
			t.Error("storePasswordResetToken が誤りを返さない")
		}
		if _, _, err := s.findPasswordResetUserID(ctx, "v"); err == nil {
			t.Error("findPasswordResetUserID が誤りを返さない")
		}
		if err := s.removePasswordResetToken(ctx, "v"); err == nil {
			t.Error("removePasswordResetToken が誤りを返さない")
		}
	})
}

// resetLinkPrefix は、Java 版の開発環境の設定で送る再設定のメールのリンクの、再設定の値の前までである。
const resetLinkPrefix = "http://localhost:5173/password/reset/"

// mailedResetToken は、偽の SES が i 番目に受けたメールの再設定のリンクの、再設定の値を返す。
func mailedResetToken(t *testing.T, mailer *fakeSES, i int) string {
	t.Helper()
	body := mailedBody(t, mailer, i)
	_, rest, ok := strings.Cut(body, resetLinkPrefix)
	if !ok {
		t.Fatalf("本文 %q に再設定のリンクが無い", body)
	}
	token, _, _ := strings.Cut(rest, "\n")
	return strings.TrimSpace(token)
}

// storedPasswordHash は、利用者 id の password の列を読む。
func storedPasswordHash(t *testing.T, id uuid.UUID) string {
	t.Helper()
	return readStoredRows(t, id).User.Password.String
}

// wantResetHash は、hash が、phrase を Java 版の BCryptPasswordEncoder の既定と同じ強さ10でハッシュにした値であることを確かめる。
func wantResetHash(t *testing.T, hash, phrase string) {
	t.Helper()
	cost, err := bcrypt.Cost([]byte(hash))
	if err != nil || cost != 10 || !strings.HasPrefix(hash, "$2a$10$") {
		t.Errorf("ハッシュ %q の強さ = %d, %v, want $2a$ の10", hash, cost, err)
	}
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(phrase)); err != nil {
		t.Errorf("ハッシュ %q が新しいパスワードと合わない: %v", hash, err)
	}
}

// wantClearSessionError は、err が、Cookie を消させる 401 の *Error で、文言が message であることを確かめる。
func wantClearSessionError(t *testing.T, err error, message string) {
	t.Helper()
	var e *Error
	if !errors.As(err, &e) {
		t.Fatalf("誤り = %v, want 401 の *Error", err)
	}
	if e.Status != 401 || e.Message != message || !e.ClearSession || e.Errors == nil || len(e.Errors) != 0 {
		t.Errorf("誤り = %+v, want 401 と文言 %q と Cookie を消させる印", e, message)
	}
}

// TestPasswordReset_ThenLogin は、確認済みの利用者がパスワードの再設定を申し込むと、10分有効な再設定の値を置いて
// 再設定のリンクのメールを利用者のメールアドレスに送り、そのリンクの値で再設定すると、新しいパスワードでログインでき、
// 古いパスワードではログインできなくなることを確かめる(要件1.2)。
func TestPasswordReset_ThenLogin(t *testing.T) {
	ctx := t.Context()
	s, client, mailer := newLoginService(t)
	email := uniqueEmail()
	oldPhrase, newPhrase := "Old-Phrase-1", "N3w-Phrase-2"
	id := insertAccount(t, testAccount{email: email, hash: hashOf(t, oldPhrase), verified: true, roles: []string{"USER"}, version: 0})

	if err := s.RequestPasswordReset(ctx, email); err != nil {
		t.Fatalf("RequestPasswordReset: %v", err)
	}
	if len(mailer.got) != 1 {
		t.Fatalf("メールの送り出し = %d 回, want 1 回", len(mailer.got))
	}
	if got := strings.Join(mailer.got[0].Destination.ToAddresses, ","); got != email {
		t.Errorf("宛先 = %q, want %q", got, email)
	}
	if got, want := deref(mailer.got[0].Message.Subject.Data), passwordResetMail(s.deps.App, "").subject; got != want {
		t.Errorf("件名 = %q, want %q", got, want)
	}
	token := mailedResetToken(t, mailer, 0)
	assertTTL(t, client, passwordResetKeyPrefix+token, 10*time.Minute)
	if got, ok, err := s.findPasswordResetUserID(ctx, token); err != nil || !ok || got != id {
		t.Fatalf("再設定の値の記録 = %s, %v, %v, want %s", got, ok, err, id)
	}

	if err := s.VerifyPasswordResetToken(ctx, token); err != nil {
		t.Fatalf("VerifyPasswordResetToken: %v", err)
	}
	if err := s.ResetPassword(ctx, token, newPhrase); err != nil {
		t.Fatalf("ResetPassword: %v", err)
	}
	wantResetHash(t, storedPasswordHash(t, id), newPhrase)

	res, err := s.Login(ctx, email, newPhrase)
	if err != nil {
		t.Fatalf("新しいパスワードの Login: %v", err)
	}
	wantSession(t, s, res.Session, id, []string{"USER"}, 1)
	_, err = s.Login(ctx, email, oldPhrase)
	wantStatusError(t, err, 400, MessageLoginFailed, "")
}

// TestPasswordReset_KeepsOtherColumns は、再設定が、Java 版の User.resetPassword と UserRepository.save と同じく、
// パスワードのハッシュと更新日時だけを書き換え、確認した日時と設定待ちのメールアドレスと役割と連携の行を残し、
// 同じトランザクションで世代の番号を1つ上げることを確かめる(要件3.5)。
func TestPasswordReset_KeepsOtherColumns(t *testing.T) {
	ctx := t.Context()
	s, _, _ := newEmailVerificationService(t, completionNow, nil)
	id := uuid.New()
	u, providers := accountEmailUser(uniqueEmail())
	u.EmailVerifiedAt = oldStamp
	u.PendingEmail = someText(uniqueEmail())
	insertStoredUser(t, id, u, []string{"USER", "ADMIN"}, providers, 5)
	want := readStoredRows(t, id)
	token := "keep-" + uuid.NewString()
	if err := s.storePasswordResetToken(ctx, token, id, time.Minute); err != nil {
		t.Fatal(err)
	}

	if err := s.ResetPassword(ctx, token, "Kept-Columns-3"); err != nil {
		t.Fatalf("ResetPassword: %v", err)
	}
	got := readStoredRows(t, id)
	wantResetHash(t, got.User.Password.String, "Kept-Columns-3")
	now := javaWallClock(completionNow)
	want.User.Password = got.User.Password
	want.User.UpdatedAt = now
	want.Version = 6
	want.VersionAt = now.Time
	wantRows(t, id, want)
}

// TestPasswordReset_TokenSingleUse は、再設定の値を1回使うと記録が消え、同じ値での確かめと再設定を、
// 置いていない値と同じく 400 の「リセットリンクが無効または期限切れです。…」で断ることを確かめる(要件3.3)。
func TestPasswordReset_TokenSingleUse(t *testing.T) {
	ctx := t.Context()
	s, client, _ := newLoginService(t)
	id := insertAccount(t, testAccount{email: uniqueEmail(), hash: hashOf(t, "First-Phrase-1"), verified: true, version: 0})
	token := "once-" + uuid.NewString()
	if err := s.storePasswordResetToken(ctx, token, id, time.Minute); err != nil {
		t.Fatal(err)
	}
	if err := s.ResetPassword(ctx, token, "First-Phrase-2"); err != nil {
		t.Fatalf("1回目の ResetPassword: %v", err)
	}
	if keyExists(t, client, passwordResetKeyPrefix+token) {
		t.Error("使った再設定の値の記録が残った")
	}
	firstHash := storedPasswordHash(t, id)

	for _, tok := range []string{token, "never-" + uuid.NewString(), ""} {
		wantStatusError(t, s.VerifyPasswordResetToken(ctx, tok), 400, MessageInvalidResetLink, "")
		wantStatusError(t, s.ResetPassword(ctx, tok, "Second-Phrase-3"), 400, MessageInvalidResetLink, "")
	}
	if got := storedPasswordHash(t, id); got != firstHash {
		t.Errorf("断った再設定でハッシュが変わった: %q, want %q", got, firstHash)
	}
}

// TestPasswordReset_InvalidatesAllSessions は、再設定が、利用者のどの端末のログインの状態も使えなくすることを確かめる。
// 世代の番号を1つ上げ、ログインを続けるための値の記録と利用者ごとの集合を消す(要件3.5)。
func TestPasswordReset_InvalidatesAllSessions(t *testing.T) {
	ctx := t.Context()
	s, client, _ := newLoginService(t)
	email := uniqueEmail()
	id := insertAccount(t, testAccount{email: email, hash: hashOf(t, "Device-Phrase-1"), verified: true, roles: []string{"USER"}, version: 4})
	var sessions []SessionTokens
	for range 2 {
		res, err := s.Login(ctx, email, "Device-Phrase-1")
		if err != nil {
			t.Fatalf("Login: %v", err)
		}
		sessions = append(sessions, res.Session)
	}
	token := "sessions-" + uuid.NewString()
	if err := s.storePasswordResetToken(ctx, token, id, time.Minute); err != nil {
		t.Fatal(err)
	}

	if err := s.ResetPassword(ctx, token, "Device-Phrase-2"); err != nil {
		t.Fatalf("ResetPassword: %v", err)
	}
	if v, _, found := tokenVersionRow(t, id); !found || v != 5 {
		t.Errorf("世代の番号 = %d, %v, want 5", v, found)
	}
	if keyExists(t, client, userRefreshKeyPrefix+id.String()) {
		t.Error("ログインを続けるための値の集合が残った")
	}
	for i, sess := range sessions {
		if keyExists(t, client, refreshTokenKeyPrefix+sess.RefreshToken) {
			t.Errorf("%d 台目のログインを続けるための値の記録が残った", i+1)
		}
		_, err := s.Refresh(ctx, sess.RefreshToken)
		wantStatusError(t, err, 401, MessageUnauthenticated, "")
		if _, err := s.VerifyAccessToken(ctx, sess.AccessToken); err == nil {
			t.Errorf("%d 台目のログインの状態の値がまだ使える", i+1)
		}
	}
}

// TestPasswordReset_RequestSame204 は、再設定の申し込みが、アカウントが無いメールアドレスでも、確認の済んでいない
// アカウントでも、送り直せる間隔の中でも、誤りを返さず同じに答えることを確かめる。確認の済んでいないアカウントには、
// 再設定のメールの代わりに、目的が PASSWORD_RESET の確認のメールを、申し込んだメールアドレスに送る(要件3.6)。
func TestPasswordReset_RequestSame204(t *testing.T) {
	ctx := t.Context()

	t.Run("アカウントが無い", func(t *testing.T) {
		s, _, mailer := newLoginService(t)
		if err := s.RequestPasswordReset(ctx, uniqueEmail()); err != nil {
			t.Fatalf("RequestPasswordReset = %v, want nil", err)
		}
		if len(mailer.got) != 0 {
			t.Errorf("メールの送り出し = %d 回, want 0 回", len(mailer.got))
		}
	})

	t.Run("確認の済んでいないアカウント", func(t *testing.T) {
		s, _, mailer := newLoginService(t)
		email := uniqueEmail()
		id := insertAccount(t, testAccount{email: email, hash: hashOf(t, "Unverified-1"), version: -1})
		for range 2 {
			if err := s.RequestPasswordReset(ctx, email); err != nil {
				t.Fatalf("RequestPasswordReset = %v, want nil", err)
			}
		}
		if len(mailer.got) != 1 {
			t.Fatalf("メールの送り出し = %d 回, want 1 回(2回目は送り直せる間隔の中)", len(mailer.got))
		}
		if got := strings.Join(mailer.got[0].Destination.ToAddresses, ","); got != email {
			t.Errorf("宛先 = %q, want %q", got, email)
		}
		c, ok := s.readEmailVerificationToken(mailedToken(t, mailer, 0))
		if !ok || c.Purpose != purposePasswordReset || c.SubjectID != id || c.Email != email {
			t.Errorf("確認のリンク = %+v, %v, want 目的 PASSWORD_RESET と利用者 %s と %s", c, ok, id, email)
		}
		if strings.Contains(mailedBody(t, mailer, 0), resetLinkPrefix) {
			t.Error("確認の済んでいないアカウントに再設定のリンクを送った")
		}
	})
}

// TestPasswordReset_UserGoneClearSession は、再設定の値は有効だが値が指す利用者が居ないとき、Java 版の
// ResetPasswordUseCase と同じく、Cookie を消させる 401 の「不正なアクセスです。」で断り、値の記録を残すことを確かめる。
// 値の確かめは、記録があれば通す。
func TestPasswordReset_UserGoneClearSession(t *testing.T) {
	ctx := t.Context()
	s, client, _ := newLoginService(t)
	token := "gone-" + uuid.NewString()
	if err := s.storePasswordResetToken(ctx, token, uuid.New(), time.Minute); err != nil {
		t.Fatal(err)
	}
	if err := s.VerifyPasswordResetToken(ctx, token); err != nil {
		t.Errorf("VerifyPasswordResetToken = %v, want nil", err)
	}
	wantClearSessionError(t, s.ResetPassword(ctx, token, "Gone-Phrase-1"), MessageInvalidAccess)
	if !keyExists(t, client, passwordResetKeyPrefix+token) {
		t.Error("断った再設定で値の記録が消えた")
	}
}

// TestPasswordReset_StoredUserRejected は、値が指す利用者が Java 版の User.reconstruct の確かめに反するとき
// (2段階認証が無効な管理者)、400 で断り、パスワードと値の記録を変えないことを確かめる。
func TestPasswordReset_StoredUserRejected(t *testing.T) {
	ctx := t.Context()
	s, client, _ := newLoginService(t)
	id := insertAccount(t, testAccount{email: uniqueEmail(), hash: hashOf(t, "Admin-Phrase-1"), verified: true, roles: []string{"ADMIN"}, version: 0})
	before := storedPasswordHash(t, id)
	token := "admin-" + uuid.NewString()
	if err := s.storePasswordResetToken(ctx, token, id, time.Minute); err != nil {
		t.Fatal(err)
	}
	var e *Error
	if err := s.ResetPassword(ctx, token, "Admin-Phrase-2"); !errors.As(err, &e) || e.Status != 400 {
		t.Fatalf("ResetPassword = %v, want 400 の *Error", err)
	}
	if got := storedPasswordHash(t, id); got != before {
		t.Errorf("ハッシュが変わった: %q, want %q", got, before)
	}
	if !keyExists(t, client, passwordResetKeyPrefix+token) {
		t.Error("断った再設定で値の記録が消えた")
	}
}

// TestPasswordReset_RollsBackWhenSessionsRemain は、ログインを続けるための値を消せないとき、Java 版の @Transactional と
// 同じく、パスワードの書き換えと世代の番号の繰り上げを取り消して誤りを返すことを確かめる。再設定の値の記録は、
// Java 版と同じく、消したままになる。
func TestPasswordReset_RollsBackWhenSessionsRemain(t *testing.T) {
	ctx := t.Context()
	s, client, _ := newLoginService(t)
	id := insertAccount(t, testAccount{email: uniqueEmail(), hash: hashOf(t, "Rollback-1"), verified: true, version: 7})
	before := storedPasswordHash(t, id)
	// 集合のキーに文字列を置き、集合として読めなくする
	if err := client.Set(ctx, userRefreshKeyPrefix+id.String(), "not-a-set", time.Minute).Err(); err != nil {
		t.Fatal(err)
	}
	token := "rollback-" + uuid.NewString()
	if err := s.storePasswordResetToken(ctx, token, id, time.Minute); err != nil {
		t.Fatal(err)
	}
	if err := s.ResetPassword(ctx, token, "Rollback-2"); err == nil {
		t.Fatal("ResetPassword が誤りを返さない")
	}
	if got := storedPasswordHash(t, id); got != before {
		t.Errorf("ハッシュが取り消されない: %q, want %q", got, before)
	}
	if v, _, _ := tokenVersionRow(t, id); v != 7 {
		t.Errorf("世代の番号 = %d, want 7(取り消し)", v)
	}
	if keyExists(t, client, passwordResetKeyPrefix+token) {
		t.Error("再設定の値の記録が残った(Java 版は消したままにする)")
	}
}

// TestPasswordReset_BrokenRecord は、再設定の値の記録が UUID でないとき、Java 版が UUID.fromString の例外で 500 に
// するのと同じく、確かめと再設定が、答えの決まった *Error でない誤りを返すことを確かめる。
func TestPasswordReset_BrokenRecord(t *testing.T) {
	ctx := t.Context()
	s, client, _ := newLoginService(t)
	token := "broken-" + uuid.NewString()
	if err := client.Set(ctx, passwordResetKeyPrefix+token, `"not-a-uuid"`, time.Minute).Err(); err != nil {
		t.Fatal(err)
	}
	var e *Error
	for name, err := range map[string]error{
		"VerifyPasswordResetToken": s.VerifyPasswordResetToken(ctx, token),
		"ResetPassword":            s.ResetPassword(ctx, token, "Broken-Phrase-1"),
	} {
		if !errors.Is(err, errPasswordResetUserID) || errors.As(err, &e) {
			t.Errorf("%s = %v, want 500 になる誤り", name, err)
		}
	}
}

// TestPasswordReset_MailFailure は、確認済みの利用者への再設定のメールを送れないとき、Java 版と同じく誤りを返すことを確かめる。
func TestPasswordReset_MailFailure(t *testing.T) {
	ctx := t.Context()
	s, _, mailer := newLoginService(t)
	email := uniqueEmail()
	insertAccount(t, testAccount{email: email, hash: hashOf(t, "Mail-Phrase-1"), verified: true, version: 0})
	mailer.err = errors.New("SES が断った")
	if err := s.RequestPasswordReset(ctx, email); err == nil {
		t.Fatal("RequestPasswordReset が誤りを返さない")
	}
	if len(mailer.got) != 1 {
		t.Errorf("メールの送り出し = %d 回, want 1 回", len(mailer.got))
	}
}
