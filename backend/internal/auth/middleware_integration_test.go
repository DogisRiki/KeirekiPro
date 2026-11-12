package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// requestWithToken は、Cookie accessToken に token を持つ GET の要求を作る。
func requestWithToken(path, token string) *http.Request {
	r := httptest.NewRequest(http.MethodGet, path, nil)
	r.Header.Add("Cookie", "accessToken="+token)
	return r
}

// TestIdentify_InvalidTokenClearsCookie は、受け付けない値を持つ要求に、Java 版と同じ、Cookie を消す Set-Cookie を足し、
// 利用者の無い要求として次に渡すことを確かめる。断るのは、そのあとのログインを求める段である。
func TestIdentify_InvalidTokenClearsCookie(t *testing.T) {
	now := time.Date(2026, 11, 11, 4, 5, 6, 0, time.UTC)
	svc := newDBTokenService(now)
	id := insertTestUser(t, 0)
	old, err := svc.IssueAccessToken(t.Context(), id, []string{"USER"})
	if err != nil {
		t.Fatalf("IssueAccessToken: %v", err)
	}
	if err := svc.BumpTokenVersion(t.Context(), sqlcgen.New(testPool), id); err != nil {
		t.Fatalf("BumpTokenVersion: %v", err)
	}
	expired, err := newDBTokenService(now.Add(-time.Hour)).IssueAccessToken(t.Context(), id, nil)
	if err != nil {
		t.Fatalf("IssueAccessToken: %v", err)
	}
	cases := map[string]string{
		"世代の番号が古い": old,
		"期限切れ":     expired,
		"値の形でない":   "not-a-jwt",
		"空":        "",
	}
	for name, token := range cases {
		t.Run(name, func(t *testing.T) {
			var p passed
			status, header, _ := serve(t, Identify(svc)(p.handler()), requestWithToken("/api/users/me", token))
			if status != http.StatusTeapot || !p.called || p.hasID {
				t.Errorf("次の処理 = %+v, 状態の番号 %d, want 利用者の無い要求として渡す", p, status)
			}
			want := "accessToken=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
			if got := header.Values("Set-Cookie"); len(got) != 1 || got[0] != want {
				t.Errorf("Set-Cookie = %q, want [%q]", got, want)
			}
			// ログインを求める段と続けると、Cookie を消したうえで 401 になる。
			var q passed
			status, header, _ = serve(t, Identify(svc)(RequireLogin()(q.handler())), requestWithToken("/api/users/me", token))
			if status != http.StatusUnauthorized || q.called || len(header.Values("Set-Cookie")) != 1 {
				t.Errorf("続けた応答 = %d, Set-Cookie %q, 次に渡した %t, want 401 と Cookie の削除", status, header.Values("Set-Cookie"), q.called)
			}
		})
	}
}

// TestIdentify_DoesNotCheckUserExists は、Java 版と同じく、値が指す利用者がまだ居るかを確かめないことを確かめる。
// 退会して行が消えた利用者の値も、世代の番号が合えば通る。断るのは、その先の操作ごとの処理である。
func TestIdentify_DoesNotCheckUserExists(t *testing.T) {
	now := time.Date(2026, 11, 11, 4, 5, 6, 0, time.UTC)
	svc := newDBTokenService(now)
	id := insertTestUser(t, 0)
	token, err := svc.IssueAccessToken(t.Context(), id, []string{"USER"})
	if err != nil {
		t.Fatalf("IssueAccessToken: %v", err)
	}
	// 利用者の行を消すと、世代の番号の行も消え、世代の番号は 0 として読まれる。
	if _, err := testPool.Exec(t.Context(), `DELETE FROM users WHERE id = $1::uuid`, id.String()); err != nil {
		t.Fatalf("利用者の行を消せない: %v", err)
	}
	var p passed
	status, header, _ := serve(t, Identify(svc)(RequireLogin()(p.handler())), requestWithToken("/api/users/me", token))
	if status != http.StatusTeapot || !p.called || !p.hasID || p.userID != id {
		t.Errorf("次の処理 = %+v, 状態の番号 %d, want 利用者 %s を持つ要求として渡す", p, status, id)
	}
	if got := header.Values("Set-Cookie"); len(got) != 0 {
		t.Errorf("Set-Cookie = %q, want 無し", got)
	}
}

// TestIdentify_DBError500 は、データベースが読めないとき、要求を次に渡さず、Cookie も消さずに、
// データベースの誤りを持つパニックで処理を打ち切ることを確かめる。
// 外側のパニックの受け止め(internal/httpapi/middleware の Recover)が、誤りをログに書き、決まった本文の 500 で答える。
// Java 版のフィルタも JWTVerificationException だけを受け止め、データベースの誤りでは要求を止める。
func TestIdentify_DBError500(t *testing.T) {
	now := time.Date(2026, 11, 11, 4, 5, 6, 0, time.UTC)
	id := insertTestUser(t, 0)
	token, err := newDBTokenService(now).IssueAccessToken(t.Context(), id, nil)
	if err != nil {
		t.Fatalf("IssueAccessToken: %v", err)
	}
	closed, err := pgxpool.New(t.Context(), testPool.Config().ConnString())
	if err != nil {
		t.Fatalf("接続の束を作れない: %v", err)
	}
	closed.Close()
	svc := New(Deps{
		Pool: closed,
		JWT:  config.JWT{Secret: testSigningKey, AccessTokenValidity: 10 * time.Minute},
		Now:  func() time.Time { return now },
	})
	var p passed
	rec := httptest.NewRecorder()
	recovered := func() (v any) {
		defer func() { v = recover() }()
		Identify(svc)(p.handler()).ServeHTTP(rec, requestWithToken("/api/users/me", token))
		return nil
	}()
	err, ok := recovered.(error)
	if !ok || errors.Is(err, ErrInvalidToken) || errors.Is(err, http.ErrAbortHandler) {
		t.Fatalf("パニックの値 = %v, want ErrInvalidToken でもhttp.ErrAbortHandler でもない誤り", recovered)
	}
	if !strings.Contains(err.Error(), "世代の番号を読めない") {
		t.Errorf("パニックの誤り %v が、データベースの誤りを包んでいない", err)
	}
	if p.called {
		t.Error("データベースが読めないのに、要求を次に渡した")
	}
	res := rec.Result()
	defer func() { _ = res.Body.Close() }()
	if got := res.Header.Values("Set-Cookie"); len(got) != 0 {
		t.Errorf("Set-Cookie = %q, want 無し", got)
	}
}

// javaIssuedToken は、Java 版の JwtProvider.createAccessToken と同じヘッダと項目と鍵で、値を作る。
// golang-jwt を使わずに組み立て、HMAC-SHA256 で署名する。
func javaIssuedToken(sub string, roles string, version int64, iat time.Time) string {
	enc := base64.RawURLEncoding
	header := enc.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`))
	payload := enc.EncodeToString(fmt.Appendf(nil, `{"sub":%q,"roles":%s,"tokenVersion":%d,"iat":%d,"exp":%d}`,
		sub, roles, version, iat.Unix(), iat.Add(10*time.Minute).Unix()))
	mac := hmac.New(sha256.New, []byte(testSigningKey))
	mac.Write([]byte(header + "." + payload))
	return header + "." + payload + "." + enc.EncodeToString(mac.Sum(nil))
}

// TestIdentify_AcceptsJavaIssuedToken は、Java 版が発行した形の値を持つ要求を、利用者と役割を context に入れて
// 次の処理に渡すことを確かめる。Java 版でログインした利用者は、Go 版に替わってもログインしたままでいられる。
func TestIdentify_AcceptsJavaIssuedToken(t *testing.T) {
	now := time.Date(2026, 11, 11, 4, 5, 6, 0, time.UTC)
	svc := newDBTokenService(now.Add(30 * time.Second))
	id := insertTestUser(t, 2)
	cases := []struct {
		name      string
		roles     string
		wantRoles []string
	}{
		{"役割が2つ", `["USER","ADMIN"]`, []string{"USER", "ADMIN"}},
		{"役割が空", `[]`, []string{}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var p passed
			token := javaIssuedToken(id.String(), tc.roles, 2, now)
			status, header, _ := serve(t, Identify(svc)(RequireLogin()(p.handler())), requestWithToken("/api/users/me", token))
			if status != http.StatusTeapot || !p.called || !p.hasID || p.userID != id || !slices.Equal(p.roles, tc.wantRoles) {
				t.Errorf("次の処理 = %+v, 状態の番号 %d, want 利用者 %s と役割 %q", p, status, id, tc.wantRoles)
			}
			if got := header.Values("Set-Cookie"); len(got) != 0 {
				t.Errorf("Set-Cookie = %q, want 無し", got)
			}
		})
	}
	// 世代の番号が違えば、Java 版が発行した形の値も断る。
	var p passed
	_, header, _ := serve(t, Identify(svc)(p.handler()), requestWithToken("/api/users/me", javaIssuedToken(id.String(), `["USER"]`, 1, now)))
	if p.hasID || len(header.Values("Set-Cookie")) != 1 {
		t.Errorf("世代の番号の違う値を受け付けた: %+v", p)
	}
}
