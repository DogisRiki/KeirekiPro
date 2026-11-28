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

// TestRegistration_FindByEmailCreatedAtMissing は、作った日時の無い記録を、最も古い記録として並べることを確かめる。
// 作った日時の無い記録は、どの版も書かない(変えた動きの一覧の CB-132)。
func TestRegistration_FindByEmailCreatedAtMissing(t *testing.T) {
	ctx := t.Context()
	s, _ := newRedisService(t)
	email := uniqueEmail()
	noDate := pendingRegistration{ID: uuid.New(), Email: email, PasswordHash: "h", Username: "u"}
	dated := pendingRegistration{ID: uuid.New(), Email: email, PasswordHash: "h", Username: "u", CreatedAt: time.Date(2026, 11, 11, 7, 8, 40, 0, time.UTC)}
	for _, r := range []pendingRegistration{noDate, dated} {
		if err := s.savePendingRegistration(ctx, r, time.Minute); err != nil {
			t.Fatal(err)
		}
	}
	got, err := s.findPendingRegistrationsByEmail(ctx, email, maxPendingRegistrations)
	if err != nil || !slices.Equal(got, []pendingRegistration{dated, noDate}) {
		t.Errorf("結果 = %+v, %v, want 作った日時のある記録、無い記録の順", got, err)
	}
}

// TestRegistration_FindByEmailMembers は、集合の要素を、JSON の文字列にした形とそのままの形のどちらでも UUID として読み、
// UUID として読めない要素を誤りにすることを確かめる。
func TestRegistration_FindByEmailMembers(t *testing.T) {
	ctx := t.Context()
	s, client := newRedisService(t)
	for _, member := range []string{`"zz"`, `123`, `abc`, `"` + uuid.NewString() + `0"`, `"` + uuid.NewString()} {
		email := uniqueEmail()
		if err := client.SAdd(ctx, "pending-registration:email:"+email, member).Err(); err != nil {
			t.Fatal(err)
		}
		if _, err := s.findPendingRegistrationsByEmail(ctx, email, maxPendingRegistrations); err == nil {
			t.Errorf("要素 %s で誤りにならない", member)
		}
	}
	// どの形の要素でも読み、記録は小文字のキーで探す。そのままの形と、大文字、ハイフンの無い形、波括弧で囲んだ形は、
	// どの版も書かない(変えた動きの一覧の CB-132)
	for _, form := range []func(string) string{
		func(id string) string { return `"` + id + `"` },
		func(id string) string { return id },
		func(id string) string { return `"` + strings.ToUpper(id) + `"` },
		func(id string) string { return `"` + strings.ReplaceAll(id, "-", "") + `"` },
		func(id string) string { return `"{` + id + `}"` },
	} {
		r := pendingRegistration{ID: uuid.New(), Email: uniqueEmail(), PasswordHash: "h", Username: "u", CreatedAt: time.Now().UTC()}
		if err := s.savePendingRegistration(ctx, r, time.Minute); err != nil {
			t.Fatal(err)
		}
		emailKey := "pending-registration:email:" + r.Email
		if err := client.Del(ctx, emailKey).Err(); err != nil {
			t.Fatal(err)
		}
		member := form(r.ID.String())
		if err := client.SAdd(ctx, emailKey, member).Err(); err != nil {
			t.Fatal(err)
		}
		got, err := s.findPendingRegistrationsByEmail(ctx, r.Email, maxPendingRegistrations)
		if err != nil || len(got) != 1 || got[0].ID != r.ID {
			t.Errorf("要素 %s の結果 = %+v, %v", member, got, err)
		}
	}
	// 記録の無い要素は、置かれた形のまま集合から除く
	email := uniqueEmail()
	if err := client.SAdd(ctx, "pending-registration:email:"+email, uuid.NewString()).Err(); err != nil {
		t.Fatal(err)
	}
	if got, err := s.findPendingRegistrationsByEmail(ctx, email, maxPendingRegistrations); err != nil || len(got) != 0 {
		t.Errorf("記録の無い要素の結果 = %+v, %v, want 空", got, err)
	}
	if n := len(setMembers(t, client, "pending-registration:email:"+email)); n != 0 {
		t.Errorf("集合の要素の数 = %d, want 0", n)
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
// 集合の要素は、JSON の文字列にした形と、そのままの形の、どちらも除く。
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
	if err := client.SAdd(ctx, "pending-registration:email:"+email, a.ID.String()).Err(); err != nil {
		t.Fatal(err)
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

// registrationCases は、記録の中の JSON inner を JSON の文字列にして置いたときに、Go 版が読む記録である。
// __ID__ は記録のキーの ID に置き換える。want が nil のときは、encoding/json で記録として読めないか、ID が無いので、
// 無い記録として扱う。どの版も書くのは最初の2つの形だけで、ほかは、どの版も書かない形である(変えた動きの一覧の CB-132)。
var registrationCases = []struct {
	name, inner string
	want        *pendingRegistration
}{
	{"9桁の作った日時", `{"id":"__ID__","email":"e","passwordHash":"h","username":"u","createdAt":"2026-11-11T07:08:40.334660199Z"}`, &pendingRegistration{Email: "e", PasswordHash: "h", Username: "u", CreatedAt: time.Date(2026, 11, 11, 7, 8, 40, 334660199, time.UTC)}},
	{"秒より細かい部分が無い", `{"id":"__ID__","createdAt":"2026-11-11T07:08:40Z"}`, &pendingRegistration{CreatedAt: time.Date(2026, 11, 11, 7, 8, 40, 0, time.UTC)}},
	{"秒より細かい部分が1桁", `{"id":"__ID__","createdAt":"2026-11-11T07:08:40.1Z"}`, &pendingRegistration{CreatedAt: time.Date(2026, 11, 11, 7, 8, 40, 100000000, time.UTC)}},
	{"時差の付いた日時", `{"id":"__ID__","createdAt":"2026-11-11T16:08:40+09:00"}`, &pendingRegistration{CreatedAt: time.Date(2026, 11, 11, 7, 8, 40, 0, time.UTC)}},
	{"作った日時が null", `{"id":"__ID__","createdAt":null}`, &pendingRegistration{}},
	{"作った日時が無い", `{"id":"__ID__"}`, &pendingRegistration{}},
	{"パスワードのハッシュが null", `{"id":"__ID__","passwordHash":null}`, &pendingRegistration{}},
	{"知らない項目", `{"id":"__ID__","x":1}`, &pendingRegistration{}},
	{"小文字の t と z", `{"id":"__ID__","createdAt":"2026-11-11t07:08:40z"}`, nil},
	{"秒の数", `{"id":"__ID__","createdAt":1762844920}`, nil},
	{"秒の数の文字列", `{"id":"__ID__","createdAt":"1762844920"}`, nil},
	{"作った日時が空の文字列", `{"id":"__ID__","createdAt":""}`, nil},
	{"作った日時の前に空白", `{"id":"__ID__","createdAt":" 2026-11-11T07:08:40Z"}`, nil},
	{"時差の無い日時", `{"id":"__ID__","createdAt":"2026-11-11T07:08:40"}`, nil},
	{"日時でない文字列", `{"id":"__ID__","createdAt":"x"}`, nil},
	{"作った日時が真偽", `{"id":"__ID__","createdAt":true}`, nil},
	{"パスワードのハッシュが数", `{"id":"__ID__","passwordHash":5}`, nil},
	{"パスワードのハッシュがオブジェクト", `{"id":"__ID__","passwordHash":{}}`, nil},
	{"利用者の名前が真偽", `{"id":"__ID__","username":true}`, nil},
	{"ID が無い", `{"email":"e"}`, nil},
	{"ID が全部 0", `{"id":"00000000-0000-0000-0000-000000000000","email":"e"}`, nil},
	{"ID が UUID でない", `{"id":"zz"}`, nil},
	{"あとの文字", `{"id":"__ID__"}}`, nil},
	{"中の JSON が null", `null`, nil},
	{"並び", `[1]`, nil},
	{"空", ``, nil},
}

// TestRegistration_ReadsRecord は、記録の中の JSON を encoding/json で読み、読めない記録と ID の無い記録を、
// 無い記録として扱うことを確かめる。
func TestRegistration_ReadsRecord(t *testing.T) {
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
			want.ID = id
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

// TestRegistration_ValueForms は、記録の値を、JSON の文字列にした形(今の書き方)と、そのままの形(書き方を替えたあとの形)の、
// どちらで置いても読み、どちらの形でもない値を無い記録とし、閉じていない JSON の文字列を誤りにすることを確かめる。
func TestRegistration_ValueForms(t *testing.T) {
	ctx := t.Context()
	s, client := newRedisService(t)
	cases := []struct {
		name, value     string
		wantOK, wantErr bool
	}{
		{"JSON の文字列にした記録", `"{\"id\":\"__ID__\",\"email\":\"__EMAIL__\"}"`, true, false},
		{"そのままの形の記録", `{"id":"__ID__","email":"__EMAIL__"}`, true, false},
		{"値が null", `null`, false, false},
		{"値が数", `5`, false, false},
		{"値が JSON でない", `abc`, false, false},
		{"中の JSON が null", `"null"`, false, false},
		{"値が閉じていない JSON の文字列", `"{`, false, true},
	}
	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			id := uuid.New()
			email := uniqueEmail()
			value := strings.NewReplacer("__ID__", id.String(), "__EMAIL__", email).Replace(tt.value)
			if err := client.Set(ctx, "pending-registration:"+id.String(), value, time.Minute).Err(); err != nil {
				t.Fatal(err)
			}
			got, ok, err := s.findPendingRegistration(ctx, id)
			if ok != tt.wantOK || (err != nil) != tt.wantErr {
				t.Errorf("findPendingRegistration = %+v, %v, %v, want 読める %v, 誤り %v", got, ok, err, tt.wantOK, tt.wantErr)
			}
			if tt.wantOK && (got.ID != id || got.Email != email) {
				t.Errorf("記録 = %+v, want ID %s とメールアドレス %s", got, id, email)
			}
			if err := client.SAdd(ctx, "pending-registration:email:"+email, `"`+id.String()+`"`).Err(); err != nil {
				t.Fatal(err)
			}
			found, err := s.findPendingRegistrationsByEmail(ctx, email, maxPendingRegistrations)
			if (err != nil) != tt.wantErr || (err == nil && (len(found) == 1) != tt.wantOK) {
				t.Errorf("findPendingRegistrationsByEmail = %+v, %v, want 読める %v, 誤り %v", found, err, tt.wantOK, tt.wantErr)
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
