package auth

import (
	"encoding/base64"
	"errors"
	"slices"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// refreshValidity は、Java 版の jwt.refresh-token-validity-in-days と、Go 版の設定の初めの値の7日である。
const refreshValidity = 7 * 24 * time.Hour

// newRefreshService は、テストの Valkey とデータベースを使い、ログインを続けるための値の有効な時間を validity にした
// Service と、Redis に直に読み書きするクライアントを作る。random が nil なら、本番と同じ乱数を使う。
func newRefreshService(t *testing.T, validity time.Duration, random func([]byte) (int, error)) (*Service, redis.UniversalClient) {
	t.Helper()
	client := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	t.Cleanup(func() { _ = client.Close() })
	return New(Deps{
		Pool:   testPool,
		Redis:  client,
		JWT:    config.JWT{RefreshTokenValidity: validity},
		Random: random,
		Now:    func() time.Time { return time.Date(2026, 11, 11, 4, 5, 6, 0, time.UTC) },
	}), client
}

// uniqueRandom は、テストごとに違う32バイトを返す乱数の関数と、その32バイトから作られる値を返す。
func uniqueRandom() (func([]byte) (int, error), string) {
	a, b := uuid.New(), uuid.New()
	raw := append(a[:], b[:]...)
	return fixedRandom(raw), base64.RawURLEncoding.EncodeToString(raw)
}

// assertTTL は、キーの有効な時間が、want から10秒を引いた時間と want のあいだにあることを確かめる。
func assertTTL(t *testing.T, client redis.UniversalClient, key string, want time.Duration) {
	t.Helper()
	got, err := client.TTL(t.Context(), key).Result()
	if err != nil {
		t.Fatalf("TTL %s: %v", key, err)
	}
	if got <= want-10*time.Second || got > want {
		t.Errorf("%s の有効な時間 = %v, want %v", key, got, want)
	}
}

// keyExists は、キーが Redis にあるかを返す。
func keyExists(t *testing.T, client redis.UniversalClient, key string) bool {
	t.Helper()
	n, err := client.Exists(t.Context(), key).Result()
	if err != nil {
		t.Fatalf("EXISTS %s: %v", key, err)
	}
	return n == 1
}

// setMembers は、集合の要素を、Redis に置かれたままの文字列で、並べ替えて返す。
func setMembers(t *testing.T, client redis.UniversalClient, key string) []string {
	t.Helper()
	got, err := client.SMembers(t.Context(), key).Result()
	if err != nil {
		t.Fatalf("SMEMBERS %s: %v", key, err)
	}
	slices.Sort(got)
	return got
}

// TestRefreshToken_TTL7Days は、ログインを続けるための値のハッシュと、利用者ごとの値の集合に、
// 設定の有効な時間(7日)が付くことを確かめる。設定の値を使うことを確かめるため、1時間の設定でも確かめる。
func TestRefreshToken_TTL7Days(t *testing.T) {
	for _, validity := range []time.Duration{refreshValidity, time.Hour} {
		t.Run(validity.String(), func(t *testing.T) {
			s, client := newRefreshService(t, validity, nil)
			userID := uuid.New()
			value, err := s.issueRefreshToken(t.Context(), userID, []string{"USER"}, 0)
			if err != nil {
				t.Fatalf("issueRefreshToken: %v", err)
			}
			assertTTL(t, client, "refresh-token:"+value, validity)
			assertTTL(t, client, "user-refresh-tokens:"+userID.String(), validity)
		})
	}
}

// TestRefreshToken_HashFieldsAsJSON は、ハッシュの項目と集合の要素が、Java 版の RedisRefreshTokenStore が置く形と
// バイトまで同じであることと、Java 版が置いた形のハッシュを読めることを確かめる。
// Java 版の形は、開発環境の Java 版にログインさせ、Redis に置かれた値を redis-cli で読んで確かめたものである。
// Java 版は、項目の名前をそのまま、値を JSON の文字列にして置き、世代の番号も "0" のような文字列にする。
func TestRefreshToken_HashFieldsAsJSON(t *testing.T) {
	random, want := uniqueRandom()
	s, client := newRefreshService(t, refreshValidity, random)
	userID := uuid.New()
	value, err := s.issueRefreshToken(t.Context(), userID, []string{"ADMIN", "USER"}, 3)
	if err != nil {
		t.Fatalf("issueRefreshToken: %v", err)
	}
	if value != want {
		t.Fatalf("値 = %q, want 乱数の32バイトの base64url の %q", value, want)
	}
	fields, err := client.HGetAll(t.Context(), "refresh-token:"+value).Result()
	if err != nil {
		t.Fatal(err)
	}
	wantFields := map[string]string{
		"userId":       `"` + userID.String() + `"`,
		"roles":        `"ADMIN,USER"`,
		"tokenVersion": `"3"`,
	}
	if len(fields) != len(wantFields) {
		t.Errorf("ハッシュの項目 = %v, want %v", fields, wantFields)
	}
	for name, w := range wantFields {
		if fields[name] != w {
			t.Errorf("項目 %s = %q, want %q", name, fields[name], w)
		}
	}
	if got := setMembers(t, client, "user-refresh-tokens:"+userID.String()); !slices.Equal(got, []string{`"` + value + `"`}) {
		t.Errorf("集合の要素 = %q, want [%q]", got, `"`+value+`"`)
	}

	t.Run("Java 版が置いた形のハッシュを読む", func(t *testing.T) {
		cases := []struct {
			name   string
			fields map[string]string
			want   refreshTokenInfo
		}{
			{
				name:   "役割が1つ",
				fields: map[string]string{"userId": `"0d104c04-67c2-4e4b-bb33-55373dfbb980"`, "roles": `"USER"`, "tokenVersion": `"0"`},
				want:   refreshTokenInfo{UserID: uuid.MustParse("0d104c04-67c2-4e4b-bb33-55373dfbb980"), Roles: []string{"USER"}, TokenVersion: 0},
			},
			{
				name:   "役割が2つ",
				fields: map[string]string{"userId": `"0d104c04-67c2-4e4b-bb33-55373dfbb980"`, "roles": `"USER,ADMIN"`, "tokenVersion": `"12"`},
				want:   refreshTokenInfo{UserID: uuid.MustParse("0d104c04-67c2-4e4b-bb33-55373dfbb980"), Roles: []string{"USER", "ADMIN"}, TokenVersion: 12},
			},
			{
				name:   "役割が無い",
				fields: map[string]string{"userId": `"0d104c04-67c2-4e4b-bb33-55373dfbb980"`, "roles": `""`, "tokenVersion": `"1"`},
				want:   refreshTokenInfo{UserID: uuid.MustParse("0d104c04-67c2-4e4b-bb33-55373dfbb980"), Roles: []string{}, TokenVersion: 1},
			},
		}
		for _, c := range cases {
			t.Run(c.name, func(t *testing.T) {
				key := "refresh-token:java-" + uuid.NewString()
				if err := client.HSet(t.Context(), key, c.fields).Err(); err != nil {
					t.Fatal(err)
				}
				got, found, err := s.findRefreshToken(t.Context(), key[len("refresh-token:"):])
				if err != nil || !found {
					t.Fatalf("findRefreshToken = %v, %v, want 見つかる", found, err)
				}
				if got.UserID != c.want.UserID || got.TokenVersion != c.want.TokenVersion || !slices.Equal(got.Roles, c.want.Roles) || got.Roles == nil {
					t.Errorf("findRefreshToken = %+v, want %+v", got, c.want)
				}
			})
		}
	})

	t.Run("Go 版が置いた値を読む", func(t *testing.T) {
		got, found, err := s.findRefreshToken(t.Context(), value)
		if err != nil || !found {
			t.Fatalf("findRefreshToken = %v, %v, want 見つかる", found, err)
		}
		if got.UserID != userID || got.TokenVersion != 3 || !slices.Equal(got.Roles, []string{"ADMIN", "USER"}) {
			t.Errorf("findRefreshToken = %+v", got)
		}
	})
}

// TestRefreshToken_FindNotFound は、Java 版の find と同じく、ハッシュが無いときと、3つの項目のどれかが無いか
// JSON の文字列でないときに「無い」を返すことと、利用者の ID と世代の番号を読めないときに誤りを返すことを確かめる。
func TestRefreshToken_FindNotFound(t *testing.T) {
	s, client := newRefreshService(t, refreshValidity, nil)
	ok := map[string]string{"userId": `"0d104c04-67c2-4e4b-bb33-55373dfbb980"`, "roles": `"USER"`, "tokenVersion": `"0"`}
	with := func(name, v string) map[string]string {
		m := map[string]string{}
		for k, x := range ok {
			m[k] = x
		}
		if v == "" {
			delete(m, name)
		} else {
			m[name] = v
		}
		return m
	}
	notFound := map[string]map[string]string{
		"利用者の ID が無い":    with("userId", ""),
		"役割が無い":          with("roles", ""),
		"世代の番号が無い":       with("tokenVersion", ""),
		"世代の番号が JSON の数": with("tokenVersion", `0`),
		"役割が JSON の並び":   with("roles", `["USER"]`),
		"利用者の ID が null": with("userId", `null`),
	}
	for name, fields := range notFound {
		t.Run(name, func(t *testing.T) {
			key := "refresh-token:nf-" + uuid.NewString()
			if err := client.HSet(t.Context(), key, fields).Err(); err != nil {
				t.Fatal(err)
			}
			if _, found, err := s.findRefreshToken(t.Context(), key[len("refresh-token:"):]); found || err != nil {
				t.Errorf("findRefreshToken = %v, %v, want 無い", found, err)
			}
		})
	}
	t.Run("ハッシュが無い", func(t *testing.T) {
		if _, found, err := s.findRefreshToken(t.Context(), "missing-"+uuid.NewString()); found || err != nil {
			t.Errorf("findRefreshToken = %v, %v, want 無い", found, err)
		}
	})

	broken := map[string]map[string]string{
		"利用者の ID が UUID でない": with("userId", `"not-a-uuid"`),
		"世代の番号が数でない":         with("tokenVersion", `"x"`),
		"利用者の ID が JSON でない": with("userId", `0d104c04`),
		"役割が JSON でない":       with("roles", `USER`),
		"世代の番号が JSON でない":    with("tokenVersion", `x`),
	}
	for name, fields := range broken {
		t.Run(name, func(t *testing.T) {
			key := "refresh-token:br-" + uuid.NewString()
			if err := client.HSet(t.Context(), key, fields).Err(); err != nil {
				t.Fatal(err)
			}
			if _, found, err := s.findRefreshToken(t.Context(), key[len("refresh-token:"):]); found || err == nil {
				t.Errorf("findRefreshToken = %v, %v, want 誤り", found, err)
			}
		})
	}
}

// TestRefreshToken_Remove は、Java 版の remove と同じく、ハッシュを消し、利用者の集合からその値だけを除くことを確かめる。
func TestRefreshToken_Remove(t *testing.T) {
	s, client := newRefreshService(t, refreshValidity, nil)
	userID := uuid.New()
	setKey := "user-refresh-tokens:" + userID.String()
	first, err := s.issueRefreshToken(t.Context(), userID, []string{"USER"}, 0)
	if err != nil {
		t.Fatal(err)
	}
	second, err := s.issueRefreshToken(t.Context(), userID, []string{"USER"}, 0)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.removeRefreshToken(t.Context(), first); err != nil {
		t.Fatalf("removeRefreshToken: %v", err)
	}
	if keyExists(t, client, "refresh-token:"+first) {
		t.Error("消した値のハッシュが残っている")
	}
	if !keyExists(t, client, "refresh-token:"+second) {
		t.Error("消していない値のハッシュが消えた")
	}
	if got := setMembers(t, client, setKey); !slices.Equal(got, []string{`"` + second + `"`}) {
		t.Errorf("集合の要素 = %q, want 消していない値だけ", got)
	}

	t.Run("利用者の ID が JSON でないときは、消さずに誤りを返す", func(t *testing.T) {
		key := "refresh-token:rm-" + uuid.NewString()
		if err := client.HSet(t.Context(), key, "userId", "not-json").Err(); err != nil {
			t.Fatal(err)
		}
		if err := s.removeRefreshToken(t.Context(), key[len("refresh-token:"):]); err == nil {
			t.Error("removeRefreshToken が誤りを返さない")
		}
		if !keyExists(t, client, key) {
			t.Error("ハッシュが消えた")
		}
	})

	t.Run("無い値を消しても誤りにしない", func(t *testing.T) {
		if err := s.removeRefreshToken(t.Context(), "missing-"+uuid.NewString()); err != nil {
			t.Errorf("removeRefreshToken = %v, want nil", err)
		}
	})

	t.Run("利用者の ID の無いハッシュは、ハッシュだけを消す", func(t *testing.T) {
		key := "refresh-token:" + second
		if err := client.HDel(t.Context(), key, "userId").Err(); err != nil {
			t.Fatal(err)
		}
		if err := s.removeRefreshToken(t.Context(), second); err != nil {
			t.Fatalf("removeRefreshToken: %v", err)
		}
		if keyExists(t, client, key) {
			t.Error("ハッシュが残っている")
		}
		if got := setMembers(t, client, setKey); !slices.Equal(got, []string{`"` + second + `"`}) {
			t.Errorf("集合の要素 = %q, want そのまま", got)
		}
	})
}

// TestInvalidateSessions_RemovesAllTokens は、Java 版の AuthSessionInvalidator と同じく、ログインの状態の世代の番号を
// 1つ上げ、利用者が持つログインを続けるための値をすべて消し、利用者の集合も消すことを確かめる。
// ほかの利用者の値は残る。
func TestInvalidateSessions_RemovesAllTokens(t *testing.T) {
	s, client := newRefreshService(t, refreshValidity, nil)
	ctx := t.Context()
	userID := insertTestUser(t, 2)
	other := insertTestUser(t, 0)
	var mine []string
	for range 3 {
		v, err := s.issueRefreshToken(ctx, userID, []string{"USER"}, 2)
		if err != nil {
			t.Fatal(err)
		}
		mine = append(mine, v)
	}
	theirs, err := s.issueRefreshToken(ctx, other, []string{"USER"}, 0)
	if err != nil {
		t.Fatal(err)
	}
	setKey := "user-refresh-tokens:" + userID.String()
	// Java 版の removeAllByUser は、文字列でない要素を飛ばす
	if err := client.SAdd(ctx, setKey, `5`).Err(); err != nil {
		t.Fatal(err)
	}

	if err := s.invalidateSessions(ctx, userID); err != nil {
		t.Fatalf("invalidateSessions: %v", err)
	}
	for _, v := range mine {
		if keyExists(t, client, "refresh-token:"+v) {
			t.Errorf("値 %s のハッシュが残っている", v)
		}
	}
	if keyExists(t, client, setKey) {
		t.Error("利用者の集合が残っている")
	}
	if version, _, _ := tokenVersionRow(t, userID); version != 3 {
		t.Errorf("世代の番号 = %d, want 3", version)
	}
	if !keyExists(t, client, "refresh-token:"+theirs) || !keyExists(t, client, "user-refresh-tokens:"+other.String()) {
		t.Error("ほかの利用者の値が消えた")
	}
	if version, _, _ := tokenVersionRow(t, other); version != 0 {
		t.Errorf("ほかの利用者の世代の番号 = %d, want 0", version)
	}

	t.Run("値を持たない利用者でも誤りにしない", func(t *testing.T) {
		if err := s.invalidateSessions(ctx, insertTestUser(t, 0)); err != nil {
			t.Errorf("invalidateSessions = %v, want nil", err)
		}
	})
}

// TestRefreshToken_Errors は、Redis とデータベースと乱数の誤りを、包んで返すことを確かめる。
// データベースの誤りのとき、invalidateSessions は、Java 版と同じく、値を消さない。
func TestRefreshToken_Errors(t *testing.T) {
	ctx := t.Context()
	t.Run("乱数", func(t *testing.T) {
		s, _ := newRefreshService(t, refreshValidity, fixedRandom(make([]byte, 31)))
		if _, err := s.issueRefreshToken(ctx, uuid.New(), []string{"USER"}, 0); err == nil {
			t.Error("issueRefreshToken が誤りを返さない")
		}
	})
	t.Run("有効な時間が0", func(t *testing.T) {
		s, client := newRefreshService(t, 0, nil)
		userID := uuid.New()
		if _, err := s.issueRefreshToken(ctx, userID, []string{"USER"}, 0); err == nil {
			t.Error("issueRefreshToken が誤りを返さない")
		}
		if keyExists(t, client, "user-refresh-tokens:"+userID.String()) {
			t.Error("集合が置かれた")
		}
	})
	t.Run("Redis", func(t *testing.T) {
		closed := redisstore.New(redisstore.Options{Addr: testRedisAddr})
		if err := closed.Close(); err != nil {
			t.Fatal(err)
		}
		s := New(Deps{Pool: testPool, Redis: closed, JWT: config.JWT{RefreshTokenValidity: refreshValidity}})
		if _, err := s.issueRefreshToken(ctx, uuid.New(), []string{"USER"}, 0); err == nil {
			t.Error("issueRefreshToken が誤りを返さない")
		}
		if _, _, err := s.findRefreshToken(ctx, "v"); err == nil {
			t.Error("findRefreshToken が誤りを返さない")
		}
		if err := s.removeRefreshToken(ctx, "v"); err == nil {
			t.Error("removeRefreshToken が誤りを返さない")
		}
		if err := s.invalidateSessions(ctx, insertTestUser(t, 0)); err == nil {
			t.Error("invalidateSessions が誤りを返さない")
		}
	})
	t.Run("データベース", func(t *testing.T) {
		pool, err := pgxpool.New(ctx, testPool.Config().ConnString())
		if err != nil {
			t.Fatal(err)
		}
		pool.Close()
		s, client := newRefreshService(t, refreshValidity, nil)
		s.deps.Pool = pool
		userID := uuid.New()
		v, err := s.issueRefreshToken(ctx, userID, []string{"USER"}, 0)
		if err != nil {
			t.Fatal(err)
		}
		if err := s.invalidateSessions(ctx, userID); err == nil {
			t.Error("invalidateSessions が誤りを返さない")
		}
		if !keyExists(t, client, "refresh-token:"+v) {
			t.Error("世代の番号を上げられないのに値を消した")
		}
	})
	t.Run("Redis の誤りを包む", func(t *testing.T) {
		closed := redisstore.New(redisstore.Options{Addr: testRedisAddr})
		_ = closed.Close()
		s := New(Deps{Redis: closed})
		if _, _, err := s.findRefreshToken(ctx, "v"); !errors.Is(err, redis.ErrClosed) {
			t.Errorf("findRefreshToken = %v, want redis.ErrClosed を包む", err)
		}
	})
}
