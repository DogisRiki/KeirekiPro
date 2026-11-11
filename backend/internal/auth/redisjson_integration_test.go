package auth

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// newRedisService は、テストの Valkey につなぐ Service と、Redis に直に読み書きするクライアントを作る。
func newRedisService(t *testing.T) (*Service, redis.UniversalClient) {
	t.Helper()
	client := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	t.Cleanup(func() { _ = client.Close() })
	return New(Deps{Redis: client}), client
}

// challengeRecord は、2段階認証の途中の記録と同じく、項目の順に名前を決めた構造体である。
type challengeRecord struct {
	UserID   string `json:"userId"`
	Attempts int    `json:"attempts"`
}

// jacksonCases は、Java 版の RedisConfig が使う JsonMapper と同じ設定の JsonMapper(Jackson 3.1.8 に、
// application.yaml の use-jackson2-defaults と JsonMapperConfig の設定を当てたもの)に値を渡し、
// writeValueAsBytes が返したバイトを、そのまま want に書いたものである。
// Jackson は、< > & と U+2028 U+2029 と DEL を置き換えず、制御文字を \u と大文字の16進で書く。
// U+10000 以上の文字は、javaSamples の見本で確かめる。
var jacksonCases = []struct {
	name string
	v    any
	want string
}{
	{name: "< > & を置き換えない", v: "<a>&b", want: `"<a>&b"`},
	{name: "日本語をそのまま書く", v: "日本語", want: `"日本語"`},
	{name: "引用符と逆斜線を逃がし、斜線を逃がさない", v: `a"b\c/d`, want: `"a\"b\\c/d"`},
	{name: "改行とタブと復帰を短い形で書く", v: "l\nb\tt\rr", want: `"l\nb\tt\rr"`},
	{name: "後退と改ページを短い形で書く", v: "\b\f", want: `"\b\f"`},
	{name: "制御文字を大文字の16進で書き、DEL を置き換えない", v: "\x01\x1f\x7f", want: `"\u0001\u001F` + "\x7f" + `"`},
	{name: "U+2028 と U+2029 を置き換えない", v: "\u2028\u2029", want: "\"\u2028\u2029\""},
	{name: "逆斜線のあとの u2028 の文字を書き換えない", v: `ab\u2028`, want: `"ab\\u2028"`},
	{name: "整数", v: 7, want: `7`},
	{name: "0", v: 0, want: `0`},
	{name: "真偽", v: true, want: `true`},
	{name: "値が無い", v: nil, want: `null`},
	{name: "並び", v: []string{"x", "y"}, want: `["x","y"]`},
	{name: "構造体は項目の順に書く", v: challengeRecord{UserID: "u-1", Attempts: 0}, want: `{"userId":"u-1","attempts":0}`},
	{
		name: "JSON の文字列を、さらに JSON の文字列にする",
		v:    `{"userId":"u-1","attempts":0}`,
		want: `"{\"userId\":\"u-1\",\"attempts\":0}"`,
	},
}

// javaSamples は、Java 版の RedisConfig が Redis に置いた値のバイトの見本と、その値を置いたときに Java 版が渡した値である。
// 見本は、Java 版の RedisConfigTest と、認証の値を置く部品のテストが比べるものと同じファイルである。
// 認証の値を置く部品は、記録を JSON にした文字列を渡すので、v も JSON の文字列にしてある。
var javaSamples = []struct {
	file string
	v    string
}{
	{"template-json-string.bin", `{"a":"b","n":1}`},
	{"template-emoji-string.bin", "絵文字😀👍🏽を含む文字列"},
	{"store-2fa-challenge.bin", `{"userId":"66666666-7777-8888-9999-aaaaaaaaaaaa","attempts":0}`},
	{
		"store-pending-registration.bin",
		`{"id":"11111111-2222-3333-4444-555555555555","email":"taro@example.com","passwordHash":"$2a$10$hashhashhash",` +
			`"username":"山田太郎😀","createdAt":"2026-10-29T04:45:30.123456Z"}`,
	},
	{"store-pending-registration-email-member.bin", "11111111-2222-3333-4444-555555555555"},
}

// readJavaSample は、Java 版のテストの資源の置き場から、Redis の値の見本を読む。
func readJavaSample(t *testing.T, file string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", "..", "src", "test", "resources", "baseline-samples", "redis", file))
	if err != nil {
		t.Fatalf("見本 %s を読めない: %v", file, err)
	}
	return b
}

// TestRedisJSON_MatchesJavaSamples は、Java 版が置いた値を getJSON で読めることと、
// 同じ値を setJSON で置くと、Java 版が置いた値とバイトまで同じになることを確かめる。
// U+10000 以上の文字(絵文字)は、Java 版と同じく \uD83D\uDE00 のような2つ組で書く。
func TestRedisJSON_MatchesJavaSamples(t *testing.T) {
	s, client := newRedisService(t)
	ctx := t.Context()

	for _, tt := range javaSamples {
		t.Run(tt.file, func(t *testing.T) {
			want := readJavaSample(t, tt.file)
			key := "redisjson:sample:" + tt.file
			if err := client.Set(ctx, key, want, time.Minute).Err(); err != nil {
				t.Fatalf("SET: %v", err)
			}
			var read string
			if found, err := s.getJSON(ctx, key, &read); err != nil || !found || read != tt.v {
				t.Errorf("getJSON = %q, %v, %v, want %q, true, nil", read, found, err, tt.v)
			}
			if err := s.setJSON(ctx, key, tt.v, time.Minute); err != nil {
				t.Fatalf("setJSON: %v", err)
			}
			got, err := client.Get(ctx, key).Bytes()
			if err != nil {
				t.Fatalf("GET: %v", err)
			}
			if !bytes.Equal(got, want) {
				t.Errorf("置いた値 = %q, want %q", got, want)
			}
		})
	}
}

// TestRedisJSON_MatchesJackson は、redisjson.go の関数が Redis に置く値が、Java 版の RedisConfig が
// 置く値とバイトまで同じであることと、Java 版が置いた値を読めることを確かめる。
func TestRedisJSON_MatchesJackson(t *testing.T) {
	s, client := newRedisService(t)
	ctx := t.Context()

	t.Run("setJSON", func(t *testing.T) {
		for _, tt := range jacksonCases {
			t.Run(tt.name, func(t *testing.T) {
				key := "redisjson:set:" + tt.name
				if err := s.setJSON(ctx, key, tt.v, time.Minute); err != nil {
					t.Fatalf("setJSON: %v", err)
				}
				got, err := client.Get(ctx, key).Result()
				if err != nil {
					t.Fatalf("GET: %v", err)
				}
				if got != tt.want {
					t.Errorf("置いた値 = %q, want %q", got, tt.want)
				}
				if ttl := client.TTL(ctx, key).Val(); ttl <= 0 || ttl > time.Minute {
					t.Errorf("有効な時間 = %v, want 0 より長く1分以下", ttl)
				}
			})
		}
	})

	t.Run("getJSON は Java 版が置いた値を読む", func(t *testing.T) {
		const key = "redisjson:get"
		if err := client.Set(ctx, key, `"{\"userId\":\"u-1\",\"attempts\":2}"`, time.Minute).Err(); err != nil {
			t.Fatalf("SET: %v", err)
		}
		var text string
		found, err := s.getJSON(ctx, key, &text)
		if err != nil || !found {
			t.Fatalf("getJSON = %v, %v, want true, nil", found, err)
		}
		var rec challengeRecord
		if err := json.Unmarshal([]byte(text), &rec); err != nil {
			t.Fatalf("中の JSON を読めない: %v", err)
		}
		if rec != (challengeRecord{UserID: "u-1", Attempts: 2}) {
			t.Errorf("読んだ記録 = %+v", rec)
		}
	})

	t.Run("getJSON はキーが無いとき false を返す", func(t *testing.T) {
		var v string
		found, err := s.getJSON(ctx, "redisjson:get:missing", &v)
		if err != nil || found {
			t.Errorf("getJSON = %v, %v, want false, nil", found, err)
		}
	})

	t.Run("getJSON は JSON でない値を誤りにする", func(t *testing.T) {
		const key = "redisjson:get:broken"
		if err := client.Set(ctx, key, "not-json", time.Minute).Err(); err != nil {
			t.Fatalf("SET: %v", err)
		}
		var v string
		if _, err := s.getJSON(ctx, key, &v); err == nil {
			t.Error("JSON でない値なのに、getJSON が誤りを返さない")
		}
	})

	t.Run("setJSONNX は無いときだけ置く", func(t *testing.T) {
		const key = "redisjson:nx"
		ok, err := s.setJSONNX(ctx, key, "1", time.Minute)
		if err != nil || !ok {
			t.Fatalf("1回目の setJSONNX = %v, %v, want true, nil", ok, err)
		}
		ok, err = s.setJSONNX(ctx, key, "2", time.Minute)
		if err != nil || ok {
			t.Fatalf("2回目の setJSONNX = %v, %v, want false, nil", ok, err)
		}
		if got := client.Get(ctx, key).Val(); got != `"1"` {
			t.Errorf("置いた値 = %q, want %q", got, `"1"`)
		}
		if ttl := client.TTL(ctx, key).Val(); ttl <= 0 || ttl > time.Minute {
			t.Errorf("有効な時間 = %v, want 0 より長く1分以下", ttl)
		}
	})

	t.Run("hsetJSON と hgetallJSON", func(t *testing.T) {
		const key = "redisjson:hash"
		fields := map[string]any{"userId": "u-1", "roles": "ADMIN,USER", "tokenVersion": "0", "note": "<&>"}
		if err := s.hsetJSON(ctx, key, fields, time.Minute); err != nil {
			t.Fatalf("hsetJSON: %v", err)
		}
		raw := client.HGetAll(ctx, key).Val()
		want := map[string]string{"userId": `"u-1"`, "roles": `"ADMIN,USER"`, "tokenVersion": `"0"`, "note": `"<&>"`}
		if len(raw) != len(want) {
			t.Fatalf("置いた項目 = %q, want %q", raw, want)
		}
		for k, w := range want {
			if raw[k] != w {
				t.Errorf("項目 %s の値 = %q, want %q", k, raw[k], w)
			}
		}
		if ttl := client.TTL(ctx, key).Val(); ttl <= 0 || ttl > time.Minute {
			t.Errorf("有効な時間 = %v, want 0 より長く1分以下", ttl)
		}

		got, err := s.hgetallJSON(ctx, key)
		if err != nil {
			t.Fatalf("hgetallJSON: %v", err)
		}
		var userID string
		if err := json.Unmarshal(got["userId"], &userID); err != nil || userID != "u-1" {
			t.Errorf("userId = %q, %v, want %q", userID, err, "u-1")
		}
		if len(got) != len(want) {
			t.Errorf("読んだ項目の数 = %d, want %d", len(got), len(want))
		}
	})

	t.Run("hgetallJSON はキーが無いとき空の束を返す", func(t *testing.T) {
		got, err := s.hgetallJSON(ctx, "redisjson:hash:missing")
		if err != nil || got == nil || len(got) != 0 {
			t.Errorf("hgetallJSON = %v, %v, want 空の束, nil", got, err)
		}
	})

	t.Run("saddJSON と smembersJSON と sremJSON", func(t *testing.T) {
		const key = "redisjson:set-members"
		if err := s.saddJSON(ctx, key, time.Minute, "id-1", "id-2"); err != nil {
			t.Fatalf("saddJSON: %v", err)
		}
		raw := client.SMembers(ctx, key).Val()
		slices.Sort(raw)
		if want := []string{`"id-1"`, `"id-2"`}; !slices.Equal(raw, want) {
			t.Errorf("置いた要素 = %q, want %q", raw, want)
		}
		if ttl := client.TTL(ctx, key).Val(); ttl <= 0 || ttl > time.Minute {
			t.Errorf("有効な時間 = %v, want 0 より長く1分以下", ttl)
		}

		if err := s.sremJSON(ctx, key, "id-1"); err != nil {
			t.Fatalf("sremJSON: %v", err)
		}
		members, err := s.smembersJSON(ctx, key)
		if err != nil {
			t.Fatalf("smembersJSON: %v", err)
		}
		if len(members) != 1 {
			t.Fatalf("残った要素 = %q, want 1つ", members)
		}
		var id string
		if err := json.Unmarshal(members[0], &id); err != nil || id != "id-2" {
			t.Errorf("残った要素 = %q, %v, want %q", id, err, "id-2")
		}
	})

	t.Run("consumeJSONIfEqual は同じ値のときだけ消す", func(t *testing.T) {
		const key = "redisjson:consume"
		if err := client.Set(ctx, key, `"jti-1"`, time.Minute).Err(); err != nil {
			t.Fatalf("SET: %v", err)
		}
		ok, err := s.consumeJSONIfEqual(ctx, key, "jti-2")
		if err != nil || ok {
			t.Fatalf("違う値の consumeJSONIfEqual = %v, %v, want false, nil", ok, err)
		}
		if n := client.Exists(ctx, key).Val(); n != 1 {
			t.Fatal("違う値なのにキーが消えた")
		}
		ok, err = s.consumeJSONIfEqual(ctx, key, "jti-1")
		if err != nil || !ok {
			t.Fatalf("同じ値の consumeJSONIfEqual = %v, %v, want true, nil", ok, err)
		}
		if n := client.Exists(ctx, key).Val(); n != 0 {
			t.Error("同じ値なのにキーが残った")
		}
	})
}

// TestRedisJSON_EncodeError は、JSON にできない値を渡したとき、どの関数も Redis に書かずに誤りを返すことを確かめる。
func TestRedisJSON_EncodeError(t *testing.T) {
	s, client := newRedisService(t)
	ctx := t.Context()
	bad := make(chan int)
	const key = "redisjson:encode-error"

	if err := s.setJSON(ctx, key, bad, time.Minute); err == nil {
		t.Error("setJSON が誤りを返さない")
	}
	if _, err := s.setJSONNX(ctx, key, bad, time.Minute); err == nil {
		t.Error("setJSONNX が誤りを返さない")
	}
	if err := s.hsetJSON(ctx, key, map[string]any{"f": bad}, time.Minute); err == nil {
		t.Error("hsetJSON が誤りを返さない")
	}
	if err := s.saddJSON(ctx, key, time.Minute, bad); err == nil {
		t.Error("saddJSON が誤りを返さない")
	}
	if err := s.sremJSON(ctx, key, bad); err == nil {
		t.Error("sremJSON が誤りを返さない")
	}
	if _, err := s.consumeJSONIfEqual(ctx, key, bad); err == nil {
		t.Error("consumeJSONIfEqual が誤りを返さない")
	}
	if n := client.Exists(ctx, key).Val(); n != 0 {
		t.Error("誤りを返したのに、キーが置かれた")
	}
}

// TestRedisJSON_RedisError は、Redis に届かないとき、どの関数も誤りを返すことを確かめる。
func TestRedisJSON_RedisError(t *testing.T) {
	client := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	if err := client.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	s := New(Deps{Redis: client})
	ctx := t.Context()
	const key = "redisjson:redis-error"
	var v string

	if err := s.setJSON(ctx, key, "v", time.Minute); err == nil {
		t.Error("setJSON が誤りを返さない")
	}
	if _, err := s.setJSONNX(ctx, key, "v", time.Minute); err == nil {
		t.Error("setJSONNX が誤りを返さない")
	}
	if _, err := s.getJSON(ctx, key, &v); err == nil {
		t.Error("getJSON が誤りを返さない")
	}
	if err := s.hsetJSON(ctx, key, map[string]any{"f": "v"}, time.Minute); err == nil {
		t.Error("hsetJSON が誤りを返さない")
	}
	if _, err := s.hgetallJSON(ctx, key); err == nil {
		t.Error("hgetallJSON が誤りを返さない")
	}
	if err := s.saddJSON(ctx, key, time.Minute, "v"); err == nil {
		t.Error("saddJSON が誤りを返さない")
	}
	if _, err := s.smembersJSON(ctx, key); err == nil {
		t.Error("smembersJSON が誤りを返さない")
	}
	if err := s.sremJSON(ctx, key, "v"); err == nil {
		t.Error("sremJSON が誤りを返さない")
	}
	if _, err := s.consumeJSONIfEqual(ctx, key, "v"); err == nil {
		t.Error("consumeJSONIfEqual が誤りを返さない")
	}
}

// TestRedisJSON_RejectsNonPositiveTTL は、値を置く関数に0以下の有効な時間を渡したとき、
// Redis に書かずに誤りを返すことを確かめる。0以下の時間で EXPIRE を送ると、Redis はキーを消すためである。
// また、go-redis の SET は、0 なら有効な時間の無いキーを置き、-1 なら前の有効な時間を残すためである。
func TestRedisJSON_RejectsNonPositiveTTL(t *testing.T) {
	s, client := newRedisService(t)
	ctx := t.Context()
	const key = "redisjson:ttl"

	for _, ttl := range []time.Duration{0, -time.Second, redis.KeepTTL} {
		if err := s.setJSON(ctx, key, "v", ttl); err == nil {
			t.Errorf("有効な時間 %v の setJSON が誤りを返さない", ttl)
		}
		if ok, err := s.setJSONNX(ctx, key, "v", ttl); err == nil || ok {
			t.Errorf("有効な時間 %v の setJSONNX = %v, %v, want false と誤り", ttl, ok, err)
		}
		if err := s.hsetJSON(ctx, key, map[string]any{"f": "v"}, ttl); err == nil {
			t.Errorf("有効な時間 %v の hsetJSON が誤りを返さない", ttl)
		}
		if err := s.saddJSON(ctx, key, ttl, "v"); err == nil {
			t.Errorf("有効な時間 %v の saddJSON が誤りを返さない", ttl)
		}
	}
	if n := client.Exists(ctx, key).Val(); n != 0 {
		t.Error("誤りを返したのに、キーが置かれた")
	}
}
