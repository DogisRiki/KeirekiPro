package auth

import (
	"errors"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// sampleBcryptHash は、Java 版の見本の記録に書かれた、bcrypt のハッシュの形をまねた値である。本物のパスワードのハッシュではない。
const sampleBcryptHash = "$2a$10$hashhashhash"

// sampleRegistration は、Java 版が store-pending-registration.bin に置いた記録と同じ値の記録である。
func sampleRegistration() pendingRegistration {
	return pendingRegistration{
		ID:           uuid.MustParse("11111111-2222-3333-4444-555555555555"),
		Email:        "taro@example.com",
		PasswordHash: sampleBcryptHash,
		Username:     "山田太郎\U0001F600",
		CreatedAt:    time.Date(2026, 10, 29, 4, 45, 30, 123456000, time.UTC),
	}
}

// uniqueEmail は、テストごとに違うメールアドレスを返す。
func uniqueEmail() string {
	return "pending-" + uuid.NewString() + "@example.com"
}

// TestRegistration_RecordShape は、記録と集合の要素が、Java 版が置いた見本とバイトまで同じ形で置かれ、
// どちらにも有効な時間が付くことと、Java 版が置いた記録を Go 版が読めることを確かめる(要件4.2)。
func TestRegistration_RecordShape(t *testing.T) {
	ctx := t.Context()
	s, client := newRedisService(t)
	r := sampleRegistration()
	key := "pending-registration:" + r.ID.String()
	emailKey := "pending-registration:email:" + r.Email
	t.Cleanup(func() { _ = client.Del(ctx, key, emailKey).Err() })

	if err := s.savePendingRegistration(ctx, r, registrationLifetime); err != nil {
		t.Fatalf("savePendingRegistration: %v", err)
	}
	if got, want := rawValue(t, client, key), string(readJavaSample(t, "store-pending-registration.bin")); got != want {
		t.Errorf("記録の値 = %s\nwant %s", got, want)
	}
	if got, want := setMembers(t, client, emailKey), []string{string(readJavaSample(t, "store-pending-registration-email-member.bin"))}; !slices.Equal(got, want) {
		t.Errorf("集合の要素 = %v, want %v", got, want)
	}
	assertTTL(t, client, key, 24*time.Hour)
	assertTTL(t, client, emailKey, 24*time.Hour)

	// Java 版が置いた記録を読める
	if err := client.Set(ctx, key, readJavaSample(t, "store-pending-registration.bin"), time.Minute).Err(); err != nil {
		t.Fatal(err)
	}
	got, ok, err := s.findPendingRegistration(ctx, r.ID)
	if err != nil || !ok {
		t.Fatalf("findPendingRegistration = %v, %v", ok, err)
	}
	if got != r {
		t.Errorf("記録 = %+v, want %+v", got, r)
	}

	// 同じ ID で置き直すと上書きする
	r.Username = "上書き"
	if err := s.savePendingRegistration(ctx, r, registrationLifetime); err != nil {
		t.Fatalf("savePendingRegistration: %v", err)
	}
	got, _, err = s.findPendingRegistration(ctx, r.ID)
	if err != nil || got.Username != "上書き" {
		t.Errorf("上書きした記録の利用者の名前 = %q, %v", got.Username, err)
	}
	if n := len(setMembers(t, client, emailKey)); n != 1 {
		t.Errorf("集合の要素の数 = %d, want 1", n)
	}
}

// TestRegistration_CreatedAtFormat は、作った日時を、Java の Instant を Jackson が書く形
// (秒より細かい部分を、要る桁数に応じて0桁、3桁、6桁、9桁で書く形)で書くことを確かめる。
// 9桁は、開発環境の Java 版で登録したときに置かれた値の形である。
func TestRegistration_CreatedAtFormat(t *testing.T) {
	base := time.Date(2026, 11, 11, 7, 8, 40, 0, time.UTC)
	cases := []struct {
		nanos int
		want  string
	}{
		{0, "2026-11-11T07:08:40Z"},
		{120000000, "2026-11-11T07:08:40.120Z"},
		{123000000, "2026-11-11T07:08:40.123Z"},
		{100000, "2026-11-11T07:08:40.000100Z"},
		{334660000, "2026-11-11T07:08:40.334660Z"},
		{334660199, "2026-11-11T07:08:40.334660199Z"},
		{1, "2026-11-11T07:08:40.000000001Z"},
	}
	for _, tt := range cases {
		if got := formatJavaInstant(base.Add(time.Duration(tt.nanos))); got != tt.want {
			t.Errorf("formatJavaInstant(+%dns) = %s, want %s", tt.nanos, got, tt.want)
		}
	}
	// 時差のある日時も UTC に直して書く
	if got := formatJavaInstant(base.In(time.FixedZone("JST", 9*60*60))); got != "2026-11-11T07:08:40Z" {
		t.Errorf("formatJavaInstant(JST) = %s", got)
	}

	ctx := t.Context()
	s, client := newRedisService(t)
	r := pendingRegistration{ID: uuid.New(), Email: uniqueEmail(), PasswordHash: "h", Username: "u", CreatedAt: base.Add(334660199)}
	if err := s.savePendingRegistration(ctx, r, time.Minute); err != nil {
		t.Fatal(err)
	}
	want := jsonQuoted(t, `{"id":"`+r.ID.String()+`","email":"`+r.Email+`","passwordHash":"h","username":"u","createdAt":"2026-11-11T07:08:40.334660199Z"}`)
	if got := rawValue(t, client, "pending-registration:"+r.ID.String()); got != want {
		t.Errorf("記録の値 = %s, want %s", got, want)
	}
	got, _, err := s.findPendingRegistration(ctx, r.ID)
	if err != nil || !got.CreatedAt.Equal(r.CreatedAt) {
		t.Errorf("読んだ作った日時 = %v, %v, want %v", got.CreatedAt, err, r.CreatedAt)
	}
}

// TestRegistration_FindByEmailMax5 は、メールアドレスの記録を、作った日時の新しい順に最大5件返し、
// 有効な時間で消えた記録の ID を集合から取り除くことを確かめる(要件4.2)。
func TestRegistration_FindByEmailMax5(t *testing.T) {
	ctx := t.Context()
	s, client := newRedisService(t)
	email := uniqueEmail()
	emailKey := "pending-registration:email:" + email
	base := time.Date(2026, 11, 11, 0, 0, 0, 0, time.UTC)
	regs := make([]pendingRegistration, 7)
	for i := range regs {
		regs[i] = pendingRegistration{ID: uuid.New(), Email: email, PasswordHash: "h" + strconv.Itoa(i), Username: "u", CreatedAt: base.Add(time.Duration(i) * time.Minute)}
	}
	for _, i := range []int{3, 0, 6, 1, 5, 2, 4} {
		if err := s.savePendingRegistration(ctx, regs[i], time.Minute); err != nil {
			t.Fatal(err)
		}
	}
	other := pendingRegistration{ID: uuid.New(), Email: uniqueEmail(), PasswordHash: "h", Username: "u", CreatedAt: base.Add(time.Hour)}
	if err := s.savePendingRegistration(ctx, other, time.Minute); err != nil {
		t.Fatal(err)
	}
	// 有効な時間で消えた記録の ID
	expired := uuid.NewString()
	if err := client.SAdd(ctx, emailKey, `"`+expired+`"`).Err(); err != nil {
		t.Fatal(err)
	}

	got, err := s.findPendingRegistrationsByEmail(ctx, email, maxPendingRegistrations)
	if err != nil {
		t.Fatalf("findPendingRegistrationsByEmail: %v", err)
	}
	want := []pendingRegistration{regs[6], regs[5], regs[4], regs[3], regs[2]}
	if !slices.Equal(got, want) {
		t.Errorf("記録 = %+v\nwant %+v", got, want)
	}
	members := setMembers(t, client, emailKey)
	if len(members) != 7 || slices.Contains(members, `"`+expired+`"`) {
		t.Errorf("集合の要素 = %v, want 消えた記録の ID を除いた7件", members)
	}

	all, err := s.findPendingRegistrationsByEmail(ctx, email, 10)
	if err != nil || len(all) != 7 || all[6] != regs[0] {
		t.Errorf("上限10の結果 = %d 件, %v", len(all), err)
	}
	none, err := s.findPendingRegistrationsByEmail(ctx, uniqueEmail(), maxPendingRegistrations)
	if err != nil || none == nil || len(none) != 0 {
		t.Errorf("記録の無いメールアドレスの結果 = %v, %v, want 空の並び", none, err)
	}
}

// TestRegistration_FindByEmailCreatedAtMissing は、作った日時の無い記録を、1件だけなら返し、
// 2件以上を並べるときは、Java 版の並べ替えと同じく誤りにすることを確かめる。開発環境の Java 版で確かめた結果である。
func TestRegistration_FindByEmailCreatedAtMissing(t *testing.T) {
	ctx := t.Context()
	s, _ := newRedisService(t)
	email := uniqueEmail()
	noDate := pendingRegistration{ID: uuid.New(), Email: email, PasswordHash: "h", Username: "u"}
	if err := s.savePendingRegistration(ctx, noDate, time.Minute); err != nil {
		t.Fatal(err)
	}
	got, err := s.findPendingRegistrationsByEmail(ctx, email, maxPendingRegistrations)
	if err != nil || len(got) != 1 || got[0] != noDate {
		t.Errorf("1件の結果 = %+v, %v", got, err)
	}
	dated := pendingRegistration{ID: uuid.New(), Email: email, PasswordHash: "h", Username: "u", CreatedAt: time.Now()}
	if err := s.savePendingRegistration(ctx, dated, time.Minute); err != nil {
		t.Fatal(err)
	}
	if _, err := s.findPendingRegistrationsByEmail(ctx, email, maxPendingRegistrations); err == nil {
		t.Error("作った日時の無い記録を並べて誤りにならない")
	}
}

// TestRegistration_FindByEmailBadMember は、集合の要素が UUID の JSON の文字列でないとき、
// Java 版と同じく誤りにすることを確かめる。
func TestRegistration_FindByEmailBadMember(t *testing.T) {
	ctx := t.Context()
	s, client := newRedisService(t)
	for _, member := range []string{`"zz"`, `123`, `abc`, `"` + uuid.NewString() + `0"`, `"{` + uuid.NewString() + `}"`} {
		email := uniqueEmail()
		if err := client.SAdd(ctx, "pending-registration:email:"+email, member).Err(); err != nil {
			t.Fatal(err)
		}
		if _, err := s.findPendingRegistrationsByEmail(ctx, email, maxPendingRegistrations); err == nil {
			t.Errorf("要素 %s で誤りにならない", member)
		}
	}
	// 大文字の UUID は読み、記録は小文字のキーで探す
	r := pendingRegistration{ID: uuid.New(), Email: uniqueEmail(), PasswordHash: "h", Username: "u", CreatedAt: time.Now().UTC()}
	if err := client.Set(ctx, "pending-registration:"+r.ID.String(), jsonQuoted(t, `{"id":"`+r.ID.String()+`","email":"`+r.Email+`","passwordHash":"h","username":"u","createdAt":"`+formatJavaInstant(r.CreatedAt)+`"}`), time.Minute).Err(); err != nil {
		t.Fatal(err)
	}
	upper := `"` + strings.ToUpper(r.ID.String()) + `"`
	if err := client.SAdd(ctx, "pending-registration:email:"+r.Email, upper).Err(); err != nil {
		t.Fatal(err)
	}
	got, err := s.findPendingRegistrationsByEmail(ctx, r.Email, maxPendingRegistrations)
	if err != nil || len(got) != 1 || got[0].ID != r.ID {
		t.Errorf("大文字の要素の結果 = %+v, %v", got, err)
	}
}

// TestRegistration_Extend24h は、記録とメールアドレスの集合の有効な時間を置き直し、
// 無い記録では何もしないことを確かめる(要件4.2)。
func TestRegistration_Extend24h(t *testing.T) {
	ctx := t.Context()
	s, client := newRedisService(t)
	r := pendingRegistration{ID: uuid.New(), Email: uniqueEmail(), PasswordHash: "h", Username: "u", CreatedAt: time.Now()}
	key := "pending-registration:" + r.ID.String()
	emailKey := "pending-registration:email:" + r.Email
	if err := s.savePendingRegistration(ctx, r, time.Hour); err != nil {
		t.Fatal(err)
	}
	if err := s.extendPendingRegistration(ctx, r.ID, registrationLifetime); err != nil {
		t.Fatalf("extendPendingRegistration: %v", err)
	}
	assertTTL(t, client, key, 24*time.Hour)
	assertTTL(t, client, emailKey, 24*time.Hour)

	// 記録が無ければ、集合の有効な時間を変えない
	if err := client.Del(ctx, key).Err(); err != nil {
		t.Fatal(err)
	}
	if err := client.Expire(ctx, emailKey, time.Hour).Err(); err != nil {
		t.Fatal(err)
	}
	if err := s.extendPendingRegistration(ctx, r.ID, registrationLifetime); err != nil {
		t.Fatalf("extendPendingRegistration: %v", err)
	}
	assertTTL(t, client, emailKey, time.Hour)
	if keyExists(t, client, key) {
		t.Error("無い記録が置かれた")
	}
	if err := s.extendPendingRegistration(ctx, r.ID, 0); err == nil {
		t.Error("有効な時間が0で誤りにならない")
	}
}

// TestRegistration_Delete は、記録を消し、メールアドレスの集合から記録の ID だけを除くことを確かめる。
func TestRegistration_Delete(t *testing.T) {
	ctx := t.Context()
	s, client := newRedisService(t)
	email := uniqueEmail()
	a := pendingRegistration{ID: uuid.New(), Email: email, PasswordHash: "h", Username: "u", CreatedAt: time.Now()}
	b := pendingRegistration{ID: uuid.New(), Email: email, PasswordHash: "h", Username: "u", CreatedAt: time.Now()}
	for _, r := range []pendingRegistration{a, b} {
		if err := s.savePendingRegistration(ctx, r, time.Minute); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.deletePendingRegistration(ctx, a); err != nil {
		t.Fatalf("deletePendingRegistration: %v", err)
	}
	if keyExists(t, client, "pending-registration:"+a.ID.String()) {
		t.Error("消した記録が残った")
	}
	if got := setMembers(t, client, "pending-registration:email:"+email); !slices.Equal(got, []string{`"` + b.ID.String() + `"`}) {
		t.Errorf("集合の要素 = %v, want もう1つの記録の ID だけ", got)
	}
}

// registrationCases は、開発環境の Java 版の Redis に、記録の中の JSON inner を JSON の文字列にして置き、
// 同じメールアドレスでログインを求めて、記録を読めたか(読めないときは集合から ID が除かれる)を調べた結果である。
// __ID__ は記録のキーの ID に置き換える。want が nil のときは、Java 版が読めず、無い記録として扱った。
var registrationCases = []struct {
	name, inner string
	want        *pendingRegistration
}{
	{"9桁の作った日時", `{"id":"__ID__","email":"e","passwordHash":"h","username":"u","createdAt":"2026-11-11T07:08:40.334660199Z"}`, &pendingRegistration{Email: "e", PasswordHash: "h", Username: "u", CreatedAt: time.Date(2026, 11, 11, 7, 8, 40, 334660199, time.UTC)}},
	{"秒より細かい部分が無い", `{"id":"__ID__","createdAt":"2026-11-11T07:08:40Z"}`, &pendingRegistration{CreatedAt: time.Date(2026, 11, 11, 7, 8, 40, 0, time.UTC)}},
	{"秒より細かい部分が1桁", `{"id":"__ID__","createdAt":"2026-11-11T07:08:40.1Z"}`, &pendingRegistration{CreatedAt: time.Date(2026, 11, 11, 7, 8, 40, 100000000, time.UTC)}},
	{"時差の付いた日時", `{"id":"__ID__","createdAt":"2026-11-11T16:08:40+09:00"}`, &pendingRegistration{CreatedAt: time.Date(2026, 11, 11, 7, 8, 40, 0, time.UTC)}},
	{"小文字の t と z", `{"id":"__ID__","createdAt":"2026-11-11t07:08:40z"}`, &pendingRegistration{CreatedAt: time.Date(2026, 11, 11, 7, 8, 40, 0, time.UTC)}},
	{"秒の数", `{"id":"__ID__","createdAt":1762844920}`, &pendingRegistration{CreatedAt: time.Unix(1762844920, 0).UTC()}},
	{"小数の秒の数", `{"id":"__ID__","createdAt":1762844920.5}`, &pendingRegistration{CreatedAt: time.Unix(1762844920, 500000000).UTC()}},
	{"秒の数の文字列", `{"id":"__ID__","createdAt":"1762844920"}`, &pendingRegistration{CreatedAt: time.Unix(1762844920, 0).UTC()}},
	{"小数の秒の数の文字列", `{"id":"__ID__","createdAt":"1762844920.5"}`, &pendingRegistration{CreatedAt: time.Unix(1762844920, 500000000).UTC()}},
	{"作った日時が null", `{"id":"__ID__","createdAt":null}`, &pendingRegistration{}},
	{"作った日時が無い", `{"id":"__ID__"}`, &pendingRegistration{}},
	{"作った日時が空の文字列", `{"id":"__ID__","createdAt":""}`, &pendingRegistration{}},
	{"作った日時の前に空白", `{"id":"__ID__","createdAt":" 2026-11-11T07:08:40Z"}`, &pendingRegistration{CreatedAt: time.Date(2026, 11, 11, 7, 8, 40, 0, time.UTC)}},
	{"時差の無い日時", `{"id":"__ID__","createdAt":"2026-11-11T07:08:40"}`, nil},
	{"日時でない文字列", `{"id":"__ID__","createdAt":"x"}`, nil},
	{"作った日時が真偽", `{"id":"__ID__","createdAt":true}`, nil},
	{"作った日時が並び", `{"id":"__ID__","createdAt":[2026,11,11,7,8,40]}`, nil},
	{"パスワードのハッシュが数", `{"id":"__ID__","passwordHash":5}`, &pendingRegistration{PasswordHash: "5"}},
	{"パスワードのハッシュが null", `{"id":"__ID__","passwordHash":null}`, &pendingRegistration{}},
	{"パスワードのハッシュがオブジェクト", `{"id":"__ID__","passwordHash":{}}`, nil},
	{"パスワードのハッシュが並び", `{"id":"__ID__","passwordHash":["h"]}`, nil},
	{"利用者の名前が数", `{"id":"__ID__","username":12}`, &pendingRegistration{Username: "12"}},
	{"利用者の名前が真偽", `{"id":"__ID__","username":true}`, &pendingRegistration{Username: "true"}},
	{"ID が無い", `{"email":"e"}`, &pendingRegistration{ID: uuid.Nil, Email: "e"}},
	{"ID が UUID でない", `{"id":"zz"}`, nil},
	{"知らない項目", `{"id":"__ID__","x":1}`, &pendingRegistration{}},
	{"あとの文字", `{"id":"__ID__"}}`, &pendingRegistration{}},
	{"並び", `[1]`, nil},
	{"空", ``, nil},
}

// TestRegistration_ReadsLikeJackson は、記録の中の JSON を、Java 版の Jackson と同じ規則で読むことを、
// 開発環境の Java 版で確かめた結果と照らして確かめる。
func TestRegistration_ReadsLikeJackson(t *testing.T) {
	ctx := t.Context()
	s, client := newRedisService(t)
	for _, tt := range registrationCases {
		t.Run(tt.name, func(t *testing.T) {
			id := uuid.New()
			inner := strings.ReplaceAll(tt.inner, "__ID__", id.String())
			if err := client.Set(ctx, "pending-registration:"+id.String(), jsonQuoted(t, inner), time.Minute).Err(); err != nil {
				t.Fatal(err)
			}
			got, ok, err := s.findPendingRegistration(ctx, id)
			if err != nil {
				t.Fatalf("findPendingRegistration: %v", err)
			}
			if tt.want == nil {
				if ok {
					t.Errorf("記録 = %+v, want 読めない", got)
				}
				return
			}
			want := *tt.want
			if want.ID == uuid.Nil && strings.Contains(tt.inner, "__ID__") {
				want.ID = id
			}
			if !ok || got != want {
				t.Errorf("記録 = %+v, %v, want %+v", got, ok, want)
			}
		})
	}
	t.Run("読めない記録は集合から除く", func(t *testing.T) {
		id := uuid.New()
		email := uniqueEmail()
		if err := client.Set(ctx, "pending-registration:"+id.String(), jsonQuoted(t, `{"id":"`+id.String()+`","createdAt":"x"}`), time.Minute).Err(); err != nil {
			t.Fatal(err)
		}
		if err := client.SAdd(ctx, "pending-registration:email:"+email, `"`+id.String()+`"`).Err(); err != nil {
			t.Fatal(err)
		}
		got, err := s.findPendingRegistrationsByEmail(ctx, email, maxPendingRegistrations)
		if err != nil || len(got) != 0 {
			t.Errorf("結果 = %+v, %v, want 空", got, err)
		}
		if n := len(setMembers(t, client, "pending-registration:email:"+email)); n != 0 {
			t.Errorf("集合の要素の数 = %d, want 0", n)
		}
	})
}

// TestRegistration_ValueForms は、記録の値そのものが JSON の文字列でないときと、中の JSON が null のときに、
// Java 版と同じく、無い記録とするか誤りにすることを確かめる。
func TestRegistration_ValueForms(t *testing.T) {
	ctx := t.Context()
	s, client := newRedisService(t)
	cases := []struct {
		name, value string
		wantErr     bool
	}{
		{"値が null", `null`, false},
		{"値がオブジェクト", `{"id":"x"}`, true},
		{"値が数", `5`, true},
		{"値が JSON でない", `abc`, true},
		{"中の JSON が null", `"null"`, true},
	}
	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			id := uuid.New()
			if err := client.Set(ctx, "pending-registration:"+id.String(), tt.value, time.Minute).Err(); err != nil {
				t.Fatal(err)
			}
			_, ok, err := s.findPendingRegistration(ctx, id)
			if ok || (err != nil) != tt.wantErr {
				t.Errorf("findPendingRegistration = %v, %v, want 誤り %v", ok, err, tt.wantErr)
			}
			email := uniqueEmail()
			if err := client.SAdd(ctx, "pending-registration:email:"+email, `"`+id.String()+`"`).Err(); err != nil {
				t.Fatal(err)
			}
			if _, err := s.findPendingRegistrationsByEmail(ctx, email, maxPendingRegistrations); (err != nil) != tt.wantErr {
				t.Errorf("findPendingRegistrationsByEmail の誤り = %v, want 誤り %v", err, tt.wantErr)
			}
			if err := s.extendPendingRegistration(ctx, id, time.Minute); (err != nil) != tt.wantErr {
				t.Errorf("extendPendingRegistration の誤り = %v, want 誤り %v", err, tt.wantErr)
			}
		})
	}
}

// TestRegistration_RedisErrors は、Redis の誤りを包んで返すことを確かめる。
func TestRegistration_RedisErrors(t *testing.T) {
	ctx := t.Context()
	closed := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	if err := closed.Close(); err != nil {
		t.Fatal(err)
	}
	s := New(Deps{Redis: closed})
	r := sampleRegistration()
	checks := map[string]error{
		"save":   s.savePendingRegistration(ctx, r, time.Minute),
		"delete": s.deletePendingRegistration(ctx, r),
		"extend": s.extendPendingRegistration(ctx, r.ID, time.Minute),
	}
	_, _, checks["find"] = s.findPendingRegistration(ctx, r.ID)
	_, checks["findByEmail"] = s.findPendingRegistrationsByEmail(ctx, r.Email, maxPendingRegistrations)
	for name, err := range checks {
		if !errors.Is(err, redis.ErrClosed) {
			t.Errorf("%s の誤り = %v, want redis.ErrClosed を包む", name, err)
		}
	}
}
