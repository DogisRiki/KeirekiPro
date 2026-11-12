package auth

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"reflect"
	"slices"
	"strconv"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// newDBTokenService は、テストのデータベースを使い、今の時刻を now に決めた Service を作る。
func newDBTokenService(now time.Time) *Service {
	return New(Deps{
		Pool: testPool,
		JWT:  config.JWT{Secret: testSigningKey, AccessTokenValidity: 10 * time.Minute},
		Now:  func() time.Time { return now },
	})
}

// insertTestUser は、利用者の行を足し、その ID を返す。
// version が負でなければ、ログインの状態の世代の番号の行も足す。
func insertTestUser(t *testing.T, version int64) uuid.UUID {
	t.Helper()
	id := uuid.New()
	ctx := t.Context()
	if _, err := testPool.Exec(ctx,
		`INSERT INTO users (id, created_at, updated_at) VALUES ($1::uuid, now(), now())`, id.String()); err != nil {
		t.Fatalf("利用者の行を足せない: %v", err)
	}
	if version >= 0 {
		if _, err := testPool.Exec(ctx,
			`INSERT INTO user_token_versions (user_id, token_version, updated_at) VALUES ($1::uuid, $2, TIMESTAMP '2000-01-01 00:00:00')`,
			id.String(), version); err != nil {
			t.Fatalf("世代の番号の行を足せない: %v", err)
		}
	}
	return id
}

// tokenVersionRow は、利用者の世代の番号の行を読む。行が無ければ found は false である。
func tokenVersionRow(t *testing.T, id uuid.UUID) (version int64, updatedAt time.Time, found bool) {
	t.Helper()
	rows, err := testPool.Query(t.Context(),
		`SELECT token_version, updated_at FROM user_token_versions WHERE user_id = $1::uuid`, id.String())
	if err != nil {
		t.Fatalf("世代の番号の行を読めない: %v", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			t.Fatalf("世代の番号の行を読めない: %v", err)
		}
		return 0, time.Time{}, false
	}
	var ts pgtype.Timestamp
	if err := rows.Scan(&version, &ts); err != nil {
		t.Fatalf("世代の番号の行を読めない: %v", err)
	}
	return version, ts.Time, true
}

// decodeSegment は、値の1つの部分を、base64url として読んだバイトの並びにする。
func decodeSegment(t *testing.T, segment string) []byte {
	t.Helper()
	b, err := base64.RawURLEncoding.DecodeString(segment)
	if err != nil {
		t.Fatalf("部分 %q を base64url として読めない: %v", segment, err)
	}
	return b
}

// TestAccessToken_HeaderAndClaims は、発行した値のヘッダと項目が、Java 版の JwtProvider と同じ形であることを確かめる。
// 形が同じなので、Java 版が発行した値を Go 版が読め、Go 版が発行した値を Java 版が読める。
func TestAccessToken_HeaderAndClaims(t *testing.T) {
	now := time.Date(2026, 11, 11, 4, 5, 6, 700_000_000, time.UTC)
	cases := []struct {
		name        string
		version     int64
		roles       []string
		wantRoles   string
		wantVersion string
	}{
		{"役割が2つ、世代の番号が3", 3, []string{"USER", "ADMIN"}, `["USER","ADMIN"]`, "3"},
		{"役割が nil", 0, nil, `[]`, "0"},
		{"世代の番号の行が無い", -1, []string{"USER"}, `["USER"]`, "0"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			id := insertTestUser(t, tc.version)
			svc := newDBTokenService(now)
			token, err := svc.IssueAccessToken(t.Context(), id, tc.roles)
			if err != nil {
				t.Fatalf("IssueAccessToken: %v", err)
			}
			parts := splitToken(t, token)
			if got := string(decodeSegment(t, parts[0])); got != `{"alg":"HS256","typ":"JWT"}` {
				t.Errorf("ヘッダ = %s, want {\"alg\":\"HS256\",\"typ\":\"JWT\"}", got)
			}
			var claims map[string]json.RawMessage
			if err := json.Unmarshal(decodeSegment(t, parts[1]), &claims); err != nil {
				t.Fatalf("項目を JSON として読めない: %v", err)
			}
			want := map[string]string{
				"sub":          strconv.Quote(id.String()),
				"roles":        tc.wantRoles,
				"tokenVersion": tc.wantVersion,
				"iat":          strconv.FormatInt(now.Unix(), 10),
				"exp":          strconv.FormatInt(now.Unix()+600, 10),
			}
			got := map[string]string{}
			for k, v := range claims {
				got[k] = string(v)
			}
			if !reflect.DeepEqual(got, want) {
				t.Errorf("項目 = %v, want %v", got, want)
			}
			// 署名が、鍵の文字列の UTF-8 のバイトで作った HS256 であることを、実装とは別に確かめる。
			if _, err := jwt.Parse(token, func(*jwt.Token) (any, error) { return []byte(testSigningKey), nil },
				jwt.WithValidMethods([]string{"HS256"}), jwt.WithTimeFunc(func() time.Time { return now })); err != nil {
				t.Errorf("鍵の文字列で署名を確かめられない: %v", err)
			}
			p, err := svc.VerifyAccessToken(t.Context(), token)
			if err != nil {
				t.Fatalf("VerifyAccessToken: %v", err)
			}
			wantRoles := tc.roles
			if wantRoles == nil {
				wantRoles = []string{}
			}
			if p.UserID != id || p.Roles == nil || !slices.Equal(p.Roles, wantRoles) {
				t.Errorf("VerifyAccessToken = %+v, want UserID %s, Roles %q", p, id, wantRoles)
			}
		})
	}
}

// TestAccessToken_ExpiresIn10Minutes は、値が発行から10分だけ有効であることを確かめる。
// 10分ちょうどで断るのは、Java 版の java-jwt が exp を「今が exp より前」で確かめるのと同じである。
func TestAccessToken_ExpiresIn10Minutes(t *testing.T) {
	now := time.Date(2026, 11, 11, 4, 5, 6, 0, time.UTC)
	id := insertTestUser(t, 0)
	token, err := newDBTokenService(now).IssueAccessToken(t.Context(), id, []string{"USER"})
	if err != nil {
		t.Fatalf("IssueAccessToken: %v", err)
	}
	for _, d := range []time.Duration{0, 10*time.Minute - time.Second, 10*time.Minute - time.Nanosecond} {
		if _, err := newDBTokenService(now.Add(d)).VerifyAccessToken(t.Context(), token); err != nil {
			t.Errorf("発行の %s あとに断った: %v", d, err)
		}
	}
	for _, d := range []time.Duration{10 * time.Minute, 10*time.Minute + time.Second} {
		if _, err := newDBTokenService(now.Add(d)).VerifyAccessToken(t.Context(), token); !errors.Is(err, ErrInvalidToken) {
			t.Errorf("発行の %s あとの VerifyAccessToken = %v, want ErrInvalidToken", d, err)
		}
	}
	// 有効な時間は設定の値に従う。
	svc := New(Deps{
		Pool: testPool,
		JWT:  config.JWT{Secret: testSigningKey, AccessTokenValidity: 3 * time.Minute},
		Now:  func() time.Time { return now },
	})
	short, err := svc.IssueAccessToken(t.Context(), id, nil)
	if err != nil {
		t.Fatalf("IssueAccessToken: %v", err)
	}
	var claims struct{ Iat, Exp int64 }
	if err := json.Unmarshal(decodeSegment(t, splitToken(t, short)[1]), &claims); err != nil {
		t.Fatalf("項目を JSON として読めない: %v", err)
	}
	if claims.Exp-claims.Iat != 180 {
		t.Errorf("exp - iat = %d, want 180", claims.Exp-claims.Iat)
	}
}

// TestAccessToken_RejectsOldVersion は、世代の番号を上げたあと、上げる前に発行した値を断り、
// 上げたあとに発行した値を受け付けることを確かめる。
func TestAccessToken_RejectsOldVersion(t *testing.T) {
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
	if _, err := svc.VerifyAccessToken(t.Context(), old); !errors.Is(err, ErrInvalidToken) {
		t.Errorf("上げる前の値の VerifyAccessToken = %v, want ErrInvalidToken", err)
	}
	fresh, err := svc.IssueAccessToken(t.Context(), id, []string{"USER"})
	if err != nil {
		t.Fatalf("IssueAccessToken: %v", err)
	}
	if _, err := svc.VerifyAccessToken(t.Context(), fresh); err != nil {
		t.Errorf("上げたあとの値を断った: %v", err)
	}
	// データベースの世代の番号より大きい番号の値も断る(Java 版は等しいかだけを比べる)。
	future := validClaims(now)
	future["sub"] = id.String()
	future["tokenVersion"] = 5
	if _, err := svc.VerifyAccessToken(t.Context(), signToken(t, jwt.SigningMethodHS256, future, []byte(testSigningKey))); !errors.Is(err, ErrInvalidToken) {
		t.Errorf("大きい番号の値の VerifyAccessToken = %v, want ErrInvalidToken", err)
	}
	// 世代の番号の行が無い利用者は、番号 0 の値だけを受け付ける。
	noRow := insertTestUser(t, -1)
	for version, wantOK := range map[int]bool{0: true, 1: false} {
		c := validClaims(now)
		c["sub"] = noRow.String()
		c["tokenVersion"] = version
		_, err := svc.VerifyAccessToken(t.Context(), signToken(t, jwt.SigningMethodHS256, c, []byte(testSigningKey)))
		if wantOK && err != nil {
			t.Errorf("行が無い利用者の番号 %d の値を断った: %v", version, err)
		}
		if !wantOK && !errors.Is(err, ErrInvalidToken) {
			t.Errorf("行が無い利用者の番号 %d の値の VerifyAccessToken = %v, want ErrInvalidToken", version, err)
		}
	}
}

// TestAccessToken_BumpTokenVersion は、世代の番号を1つ上げ、updated_at を東京の時刻で書くこと、
// 行が無ければ何もしないこと、トランザクションの中でも呼べることを確かめる。
func TestAccessToken_BumpTokenVersion(t *testing.T) {
	now := time.Date(2026, 11, 11, 4, 5, 6, 123_456_000, time.UTC)
	svc := newDBTokenService(now)
	t.Run("行がある", func(t *testing.T) {
		id := insertTestUser(t, 2)
		if err := svc.BumpTokenVersion(t.Context(), sqlcgen.New(testPool), id); err != nil {
			t.Fatalf("BumpTokenVersion: %v", err)
		}
		version, updatedAt, found := tokenVersionRow(t, id)
		// Java 版は LocalDateTime.now() を Asia/Tokyo の時刻で書くので、Go 版も東京の時刻の見た目で書く。
		wantUpdated := time.Date(2026, 11, 11, 13, 5, 6, 123_456_000, time.UTC)
		if !found || version != 3 || !updatedAt.Equal(wantUpdated) {
			t.Errorf("行 = %d, %s, %t, want 3, %s, true", version, updatedAt, found, wantUpdated)
		}
	})
	t.Run("行が無い", func(t *testing.T) {
		id := insertTestUser(t, -1)
		if err := svc.BumpTokenVersion(t.Context(), sqlcgen.New(testPool), id); err != nil {
			t.Fatalf("BumpTokenVersion: %v", err)
		}
		if _, _, found := tokenVersionRow(t, id); found {
			t.Error("行が無いのに、行ができた")
		}
	})
	t.Run("トランザクションの中", func(t *testing.T) {
		id := insertTestUser(t, 0)
		tx, err := testPool.Begin(t.Context())
		if err != nil {
			t.Fatalf("トランザクションを始められない: %v", err)
		}
		if err := svc.BumpTokenVersion(t.Context(), sqlcgen.New(testPool).WithTx(tx), id); err != nil {
			t.Fatalf("BumpTokenVersion: %v", err)
		}
		if err := tx.Rollback(t.Context()); err != nil {
			t.Fatalf("トランザクションを巻き戻せない: %v", err)
		}
		if version, _, _ := tokenVersionRow(t, id); version != 0 {
			t.Errorf("巻き戻したのに、世代の番号 = %d", version)
		}
	})
}

// TestAccessToken_DatabaseError は、データベースを読めないとき、ErrInvalidToken でない誤りを返すことを確かめる。
// ErrInvalidToken にすると、データベースの障害が、利用者のログインの状態の誤りとして 401 になってしまう。
func TestAccessToken_DatabaseError(t *testing.T) {
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
	if _, err := svc.IssueAccessToken(t.Context(), id, nil); err == nil || errors.Is(err, ErrInvalidToken) {
		t.Errorf("IssueAccessToken の誤り = %v, want ErrInvalidToken でない誤り", err)
	}
	if _, err := svc.VerifyAccessToken(t.Context(), token); err == nil || errors.Is(err, ErrInvalidToken) {
		t.Errorf("VerifyAccessToken の誤り = %v, want ErrInvalidToken でない誤り", err)
	}
	if err := svc.BumpTokenVersion(t.Context(), sqlcgen.New(closed), id); err == nil {
		t.Error("BumpTokenVersion が誤りを返さない")
	}
}
