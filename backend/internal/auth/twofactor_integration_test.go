package auth

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// twoFactorTestCode は、twoFactorRandom の乱数の先頭の4バイト 0x0001E240 から作られる確認のコードである。
const twoFactorTestCode = "123456"

// newTwoFactorService は、テストの Valkey と偽の SES と、Java 版の開発環境と同じ設定の値を使う Service と、
// Redis に直に読み書きするクライアントと、偽の SES を作る。random が nil なら、本番と同じ乱数を使う。
func newTwoFactorService(t *testing.T, random func([]byte) (int, error)) (*Service, redis.UniversalClient, *fakeSES) {
	t.Helper()
	templates, err := backend.MailTemplates()
	if err != nil {
		t.Fatal(err)
	}
	client := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	t.Cleanup(func() { _ = client.Close() })
	mailer := &fakeSES{}
	return New(Deps{
		Redis:         client,
		SES:           mailer,
		App:           javaDevApp(t),
		MailTemplates: templates,
		Random:        random,
	}), client, mailer
}

// twoFactorRandom は、確認のコードの4バイトのあとに、テストごとに違う32バイトを返す乱数の関数と、
// その32バイトから作られる途中の記録の値を返す。
func twoFactorRandom() (func([]byte) (int, error), string) {
	a, b := uuid.New(), uuid.New()
	raw := append([]byte{0x00, 0x01, 0xE2, 0x40}, a[:]...)
	raw = append(raw, b[:]...)
	return fixedRandom(raw), base64.RawURLEncoding.EncodeToString(raw[4:])
}

// rawValue は、キーの値を、Redis に置かれたままのバイトで返す。キーが無ければ空の文字列を返す。
func rawValue(t *testing.T, client redis.UniversalClient, key string) string {
	t.Helper()
	v, err := client.Get(t.Context(), key).Result()
	if errors.Is(err, redis.Nil) {
		return ""
	}
	if err != nil {
		t.Fatalf("GET %s: %v", key, err)
	}
	return v
}

// jsonQuoted は、s を JSON の文字列にする。Java 版の RedisTemplate が文字列の値を置く形である。
func jsonQuoted(t *testing.T, s string) string {
	t.Helper()
	b, err := json.Marshal(s)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// wantBusinessError は、err が、文言 message の 400 の *Error であることを確かめる。
func wantBusinessError(t *testing.T, err error, message string) {
	t.Helper()
	var e *Error
	if !errors.As(err, &e) {
		t.Fatalf("誤り = %v, want 文言 %q の *Error", err, message)
	}
	if e.Status != 400 || e.Message != message || e.Errors == nil || len(e.Errors) != 0 {
		t.Errorf("誤り = %+v, want 400 と文言 %q と空の Errors", e, message)
	}
}

// TestTwoFactor_TTL10Minutes は、確認のコードと途中の記録が、10分の有効な時間で置かれることと、
// 確認のコードが6桁の数字の JSON の文字列で置かれ、同じコードがメールで送られることを確かめる(要件3.2)。
func TestTwoFactor_TTL10Minutes(t *testing.T) {
	random, wantToken := twoFactorRandom()
	s, client, mailer := newTwoFactorService(t, random)
	userID := uuid.New()

	token, err := s.issueTwoFactor(t.Context(), userID, "two-factor@example.com")
	if err != nil {
		t.Fatalf("issueTwoFactor: %v", err)
	}
	if token != wantToken {
		t.Errorf("途中の記録の値 = %q, want %q", token, wantToken)
	}
	codeKey := "2fa:" + userID.String()
	if got := rawValue(t, client, codeKey); got != `"`+twoFactorTestCode+`"` {
		t.Errorf("確認のコードの値 = %s, want \"%s\"", got, twoFactorTestCode)
	}
	assertTTL(t, client, codeKey, 10*time.Minute)
	assertTTL(t, client, "2fa:challenge:"+token, 10*time.Minute)

	if len(mailer.got) != 1 {
		t.Fatalf("SendEmail の呼び出し = %d 回, want 1 回", len(mailer.got))
	}
	in := mailer.got[0]
	if to := in.Destination.ToAddresses; len(to) != 1 || to[0] != "two-factor@example.com" {
		t.Errorf("宛先 = %v, want two-factor@example.com", to)
	}
	if got, want := deref(in.Message.Subject.Data), "【"+javaDevApp(t).SiteName+"】2段階認証コードのお知らせ"; got != want {
		t.Errorf("件名 = %q, want %q", got, want)
	}
	if body := deref(in.Message.Body.Text.Data); !strings.Contains(body, twoFactorTestCode) {
		t.Errorf("本文に確認のコード %s が無い: %q", twoFactorTestCode, body)
	}
}

// TestTwoFactor_ChallengeIsDoubleEncodedJSON は、途中の記録が、Java 版が置いた見本とバイトまで同じ形
// (JSON を、さらに JSON の文字列にした形)で置かれ、誤ったコードのあとの書き直しも見本と同じになることと、
// Java 版が置いた途中の記録を Go 版が読めることを確かめる(要件4.2)。
func TestTwoFactor_ChallengeIsDoubleEncodedJSON(t *testing.T) {
	ctx := t.Context()
	random, _ := twoFactorRandom()
	s, client, _ := newTwoFactorService(t, random)
	userID := uuid.MustParse("66666666-7777-8888-9999-aaaaaaaaaaaa")

	token, err := s.issueTwoFactor(ctx, userID, "two-factor@example.com")
	if err != nil {
		t.Fatalf("issueTwoFactor: %v", err)
	}
	key := "2fa:challenge:" + token
	if got, want := rawValue(t, client, key), string(readJavaSample(t, "store-2fa-challenge.bin")); got != want {
		t.Errorf("途中の記録の値 = %s\nwant %s", got, want)
	}
	_, err = s.checkTwoFactor(ctx, token, "000000")
	wantBusinessError(t, err, MessageInvalidTwoFactorCode)
	if got, want := rawValue(t, client, key), string(readJavaSample(t, "store-2fa-challenge-incremented.bin")); got != want {
		t.Errorf("誤ったコードのあとの途中の記録の値 = %s\nwant %s", got, want)
	}

	// Java 版が置いた途中の記録と確認のコードで、確認が通る
	const javaToken = "java-written-challenge"
	if err := client.Set(ctx, "2fa:challenge:"+javaToken, readJavaSample(t, "store-2fa-challenge.bin"), time.Minute).Err(); err != nil {
		t.Fatal(err)
	}
	if err := client.Set(ctx, "2fa:"+userID.String(), `"654321"`, time.Minute).Err(); err != nil {
		t.Fatal(err)
	}
	got, err := s.checkTwoFactor(ctx, javaToken, "654321")
	if err != nil {
		t.Fatalf("checkTwoFactor: %v", err)
	}
	if got != userID {
		t.Errorf("利用者の ID = %s, want %s", got, userID)
	}
}

// TestTwoFactor_WrongCodeKeepsTTL は、誤ったコードを受けたとき、途中の記録を残りの有効な時間のまま置き直し、
// 有効な時間が無い途中の記録は10分にして置き直し、確認のコードの有効な時間は変えないことを確かめる(要件3.2)。
func TestTwoFactor_WrongCodeKeepsTTL(t *testing.T) {
	ctx := t.Context()
	random, _ := twoFactorRandom()
	s, client, _ := newTwoFactorService(t, random)
	userID := uuid.New()
	token, err := s.issueTwoFactor(ctx, userID, "two-factor@example.com")
	if err != nil {
		t.Fatalf("issueTwoFactor: %v", err)
	}
	key := "2fa:challenge:" + token
	codeKey := "2fa:" + userID.String()
	if err := client.Expire(ctx, key, 300*time.Second).Err(); err != nil {
		t.Fatal(err)
	}
	if err := client.Expire(ctx, codeKey, 200*time.Second).Err(); err != nil {
		t.Fatal(err)
	}

	_, err = s.checkTwoFactor(ctx, token, "000000")
	wantBusinessError(t, err, MessageInvalidTwoFactorCode)
	assertTTL(t, client, key, 300*time.Second)
	assertTTL(t, client, codeKey, 200*time.Second)
	wantInner := `{"userId":"` + userID.String() + `","attempts":1}`
	if got := rawValue(t, client, key); got != jsonQuoted(t, wantInner) {
		t.Errorf("途中の記録の値 = %s, want %s", got, jsonQuoted(t, wantInner))
	}

	if err := client.Persist(ctx, key).Err(); err != nil {
		t.Fatal(err)
	}
	_, err = s.checkTwoFactor(ctx, token, "000000")
	wantBusinessError(t, err, MessageInvalidTwoFactorCode)
	assertTTL(t, client, key, 10*time.Minute)
	wantInner = `{"userId":"` + userID.String() + `","attempts":2}`
	if got := rawValue(t, client, key); got != jsonQuoted(t, wantInner) {
		t.Errorf("途中の記録の値 = %s, want %s", got, jsonQuoted(t, wantInner))
	}
}

// TestTwoFactor_FifthWrongCodeDeletes は、4回目までの誤ったコードでは途中の記録と確認のコードを残し、
// 5回目の誤ったコードで両方を消して上限の文言で断り、そのあとは正しいコードでも断ることを確かめる(要件3.2)。
func TestTwoFactor_FifthWrongCodeDeletes(t *testing.T) {
	ctx := t.Context()
	random, _ := twoFactorRandom()
	s, client, _ := newTwoFactorService(t, random)
	userID := uuid.New()
	token, err := s.issueTwoFactor(ctx, userID, "two-factor@example.com")
	if err != nil {
		t.Fatalf("issueTwoFactor: %v", err)
	}
	key := "2fa:challenge:" + token
	codeKey := "2fa:" + userID.String()

	for i := 1; i <= 4; i++ {
		_, err := s.checkTwoFactor(ctx, token, "000000")
		wantBusinessError(t, err, MessageInvalidTwoFactorCode)
		if !keyExists(t, client, key) || !keyExists(t, client, codeKey) {
			t.Fatalf("%d 回目の誤りで値が消えた", i)
		}
	}
	_, err = s.checkTwoFactor(ctx, token, "000000")
	wantBusinessError(t, err, MessageTwoFactorAttemptsExceeded)
	if keyExists(t, client, key) {
		t.Error("5回目の誤りのあとに途中の記録が残った")
	}
	if keyExists(t, client, codeKey) {
		t.Error("5回目の誤りのあとに確認のコードが残った")
	}
	_, err = s.checkTwoFactor(ctx, token, twoFactorTestCode)
	wantBusinessError(t, err, MessageInvalidTwoFactorSession)
}

// TestTwoFactor_Check は、正しいコードで利用者の ID を返して両方の値を消すことと、
// Java 版と同じ順で照らして断ることを確かめる。
func TestTwoFactor_Check(t *testing.T) {
	ctx := t.Context()
	t.Run("正しいコード", func(t *testing.T) {
		random, _ := twoFactorRandom()
		s, client, _ := newTwoFactorService(t, random)
		userID := uuid.New()
		token, err := s.issueTwoFactor(ctx, userID, "two-factor@example.com")
		if err != nil {
			t.Fatalf("issueTwoFactor: %v", err)
		}
		got, err := s.checkTwoFactor(ctx, token, twoFactorTestCode)
		if err != nil {
			t.Fatalf("checkTwoFactor: %v", err)
		}
		if got != userID {
			t.Errorf("利用者の ID = %s, want %s", got, userID)
		}
		if keyExists(t, client, "2fa:challenge:"+token) || keyExists(t, client, "2fa:"+userID.String()) {
			t.Error("確認が通ったのに値が残った")
		}
		_, err = s.checkTwoFactor(ctx, token, twoFactorTestCode)
		wantBusinessError(t, err, MessageInvalidTwoFactorSession)
	})
	t.Run("途中の記録の値が空白だけ", func(t *testing.T) {
		s, client, _ := newTwoFactorService(t, nil)
		// Java の isBlank が空白とする U+3000 と、空白としない U+00A0 を確かめる
		for _, token := range []string{"", " \t\n", "　"} {
			if err := client.Set(ctx, "2fa:challenge:"+token, jsonQuoted(t, `{"userId":null,"attempts":0}`), time.Minute).Err(); err != nil {
				t.Fatal(err)
			}
			_, err := s.checkTwoFactor(ctx, token, "000000")
			wantBusinessError(t, err, MessageInvalidTwoFactorSession)
			if !keyExists(t, client, "2fa:challenge:"+token) {
				t.Errorf("値 %q で途中の記録を読んだ", token)
			}
		}
		if err := client.Set(ctx, "2fa:challenge: ", jsonQuoted(t, `{"userId":null,"attempts":0}`), time.Minute).Err(); err != nil {
			t.Fatal(err)
		}
		if err := client.Del(ctx, "2fa:null").Err(); err != nil {
			t.Fatal(err)
		}
		_, err := s.checkTwoFactor(ctx, " ", "000000")
		wantBusinessError(t, err, MessageInvalidTwoFactorCode)
	})
	t.Run("途中の記録が無い", func(t *testing.T) {
		s, client, _ := newTwoFactorService(t, nil)
		userID := uuid.New()
		if err := client.Set(ctx, "2fa:"+userID.String(), `"123456"`, time.Minute).Err(); err != nil {
			t.Fatal(err)
		}
		_, err := s.checkTwoFactor(ctx, "no-such-challenge", "123456")
		wantBusinessError(t, err, MessageInvalidTwoFactorSession)
	})
	t.Run("確認のコードが無い", func(t *testing.T) {
		random, _ := twoFactorRandom()
		s, client, _ := newTwoFactorService(t, random)
		userID := uuid.New()
		token, err := s.issueTwoFactor(ctx, userID, "two-factor@example.com")
		if err != nil {
			t.Fatalf("issueTwoFactor: %v", err)
		}
		if err := client.Del(ctx, "2fa:"+userID.String()).Err(); err != nil {
			t.Fatal(err)
		}
		_, err = s.checkTwoFactor(ctx, token, twoFactorTestCode)
		wantBusinessError(t, err, MessageInvalidTwoFactorCode)
		if keyExists(t, client, "2fa:challenge:"+token) {
			t.Error("確認のコードが無いのに途中の記録が残った")
		}
	})
	t.Run("利用者の ID が無い途中の記録", func(t *testing.T) {
		s, client, _ := newTwoFactorService(t, nil)
		const token = "challenge-without-user"
		if err := client.Set(ctx, "2fa:challenge:"+token, jsonQuoted(t, `{"attempts":0}`), time.Minute).Err(); err != nil {
			t.Fatal(err)
		}
		if err := client.Set(ctx, "2fa:null", `"123456"`, time.Minute).Err(); err != nil {
			t.Fatal(err)
		}
		got, err := s.checkTwoFactor(ctx, token, "123456")
		if err != nil {
			t.Fatalf("checkTwoFactor: %v", err)
		}
		if got != uuid.Nil {
			t.Errorf("利用者の ID = %s, want uuid.Nil", got)
		}
		if keyExists(t, client, "2fa:challenge:"+token) || keyExists(t, client, "2fa:null") {
			t.Error("確認が通ったのに値が残った")
		}
	})
}

// jacksonUser は、TestTwoFactor_ReadsChallengeLikeJackson の途中の記録の利用者の ID である。
const jacksonUser = "11111111-2222-3333-4444-001794379977"

// jacksonChallengeCases は、開発環境の Java 版の Redis に、途中の記録 inner(を JSON の文字列にした値)と、
// 確認のコード "123456" を 2fa:<jacksonUser> と 2fa:null に置き、誤ったコード "000000" で確認を求めた結果である。
// want は、次のどれかである。
//
//   - "session": 「認証セッションが無効または期限切れです」で断り、値を変えない(Jackson が途中の記録を読めない)
//   - "error": 予期せぬ誤りの 500 になり、値を変えない
//   - "deleted": 「認証コードが無効または期限切れです」で断り、途中の記録を消す(利用者の確認のコードが無い)
//   - "limit": 「試行回数の上限に達しました」で断り、途中の記録と確認のコードを消す
//   - "{" で始まる値: 「認証コードが無効または期限切れです」で断り、途中の記録をこの JSON に書き直す
var jacksonChallengeCases = []struct {
	name, inner, want string
}{
	{"JSON でない", `abc`, "session"},
	{"空", ``, "session"},
	{"空白だけ", `  `, "session"},
	{"null", `null`, "error"},
	{"数", `5`, "session"},
	{"並び", `[1]`, "session"},
	{"閉じていない", `{"userId":"` + jacksonUser + `","attempts":0`, "session"},
	{"末尾のコンマ", `{"userId":"` + jacksonUser + `","attempts":0,}`, "session"},
	{"前の空白", `  {"userId":"` + jacksonUser + `","attempts":0}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"あとの文字", `{"userId":"` + jacksonUser + `","attempts":0}}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"2つのオブジェクト", `{"userId":"` + jacksonUser + `","attempts":0}{"attempts":3}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"知らない項目", `{"userId":"` + jacksonUser + `","attempts":0,"x":1}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"同じ項目が2回", `{"userId":"` + jacksonUser + `","attempts":3,"attempts":0}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"回数が4", `{"userId":"` + jacksonUser + `","attempts":4}`, "limit"},
	{"回数が7", `{"userId":"` + jacksonUser + `","attempts":7}`, "limit"},
	{"回数が無い", `{"userId":"` + jacksonUser + `"}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"回数が null", `{"userId":"` + jacksonUser + `","attempts":null}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"回数が負", `{"userId":"` + jacksonUser + `","attempts":-10}`, `{"userId":"` + jacksonUser + `","attempts":-9}`},
	{"回数が -0", `{"userId":"` + jacksonUser + `","attempts":-0}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"回数が小数", `{"userId":"` + jacksonUser + `","attempts":2.5}`, `{"userId":"` + jacksonUser + `","attempts":3}`},
	{"回数が負の小数", `{"userId":"` + jacksonUser + `","attempts":-2.5}`, `{"userId":"` + jacksonUser + `","attempts":-1}`},
	{"回数が 2.0", `{"userId":"` + jacksonUser + `","attempts":2.0}`, `{"userId":"` + jacksonUser + `","attempts":3}`},
	{"回数が 1e2", `{"userId":"` + jacksonUser + `","attempts":1e2}`, "limit"},
	{"回数が 1.5e1", `{"userId":"` + jacksonUser + `","attempts":1.5e1}`, "limit"},
	{"回数が 1e10", `{"userId":"` + jacksonUser + `","attempts":1e10}`, "session"},
	{"回数が int の最大", `{"userId":"` + jacksonUser + `","attempts":2147483647}`, `{"userId":"` + jacksonUser + `","attempts":-2147483648}`},
	{"回数が int の最大を越える", `{"userId":"` + jacksonUser + `","attempts":2147483648}`, "session"},
	{"回数が真偽", `{"userId":"` + jacksonUser + `","attempts":true}`, "session"},
	{"回数がオブジェクト", `{"userId":"` + jacksonUser + `","attempts":{}}`, "session"},
	{"回数が文字列の数", `{"userId":"` + jacksonUser + `","attempts":"2"}`, `{"userId":"` + jacksonUser + `","attempts":3}`},
	{"回数が前に空白の文字列", `{"userId":"` + jacksonUser + `","attempts":" 2"}`, `{"userId":"` + jacksonUser + `","attempts":3}`},
	{"回数があとに空白の文字列", `{"userId":"` + jacksonUser + `","attempts":"2 "}`, `{"userId":"` + jacksonUser + `","attempts":3}`},
	{"回数が + の付いた文字列", `{"userId":"` + jacksonUser + `","attempts":"+2"}`, `{"userId":"` + jacksonUser + `","attempts":3}`},
	{"回数が - の付いた文字列", `{"userId":"` + jacksonUser + `","attempts":"-2"}`, `{"userId":"` + jacksonUser + `","attempts":-1}`},
	{"回数が 0 で始まる文字列", `{"userId":"` + jacksonUser + `","attempts":"02"}`, `{"userId":"` + jacksonUser + `","attempts":3}`},
	{"回数が空の文字列", `{"userId":"` + jacksonUser + `","attempts":""}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"回数が空白の文字列", `{"userId":"` + jacksonUser + `","attempts":" "}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"回数が null の文字列", `{"userId":"` + jacksonUser + `","attempts":"null"}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"回数が int の最大の文字列", `{"userId":"` + jacksonUser + `","attempts":"2147483647"}`, `{"userId":"` + jacksonUser + `","attempts":-2147483648}`},
	{"回数が int の最大を越える文字列", `{"userId":"` + jacksonUser + `","attempts":"2147483648"}`, "session"},
	{"回数が数でない文字列", `{"userId":"` + jacksonUser + `","attempts":"x"}`, "session"},
	{"回数が小数の文字列", `{"userId":"` + jacksonUser + `","attempts":"2.5"}`, "session"},
	{"回数が指数の文字列", `{"userId":"` + jacksonUser + `","attempts":"1e2"}`, "session"},
	{"回数が16進の文字列", `{"userId":"` + jacksonUser + `","attempts":"0x1"}`, "session"},
	{"利用者の ID が無い", `{"attempts":0}`, `{"userId":null,"attempts":1}`},
	{"利用者の ID が空の文字列", `{"userId":"","attempts":0}`, `{"userId":null,"attempts":1}`},
	{"利用者の ID が空白の文字列", `{"userId":" ","attempts":0}`, `{"userId":null,"attempts":1}`},
	{"利用者の ID が大文字", `{"userId":"` + strings.ToUpper(jacksonUser) + `","attempts":0}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"利用者の ID の前に空白", `{"userId":" ` + jacksonUser + `","attempts":0}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"利用者の ID のあとに空白", `{"userId":"` + jacksonUser + ` ","attempts":0}`, `{"userId":"` + jacksonUser + `","attempts":1}`},
	{"利用者の ID が base64", `{"userId":"AAAAAAAAAAAAAAAAAAAAAA==","attempts":0}`, "deleted"},
	{"利用者の ID が UUID でない", `{"userId":"zz","attempts":0}`, "session"},
	{"利用者の ID にハイフンが無い", `{"userId":"` + strings.ReplaceAll(jacksonUser, "-", "") + `","attempts":0}`, "session"},
	{"利用者の ID が波括弧で囲まれる", `{"userId":"{` + jacksonUser + `}","attempts":0}`, "session"},
	{"利用者の ID が urn", `{"userId":"urn:uuid:` + jacksonUser + `","attempts":0}`, "session"},
	{"利用者の ID が数", `{"userId":123,"attempts":0}`, "session"},
	{"利用者の ID が真偽", `{"userId":true,"attempts":0}`, "session"},
	{"利用者の ID がオブジェクト", `{"userId":{},"attempts":0}`, "session"},
	{"利用者の ID が並び", `{"userId":[],"attempts":0}`, "session"},
}

// TestTwoFactor_ReadsChallengeLikeJackson は、途中の記録の中の JSON を、Java 版の Jackson と同じ規則で読むことを、
// 開発環境の Java 版で確かめた結果と照らして確かめる。
func TestTwoFactor_ReadsChallengeLikeJackson(t *testing.T) {
	ctx := t.Context()
	s, client, _ := newTwoFactorService(t, nil)
	userCodeKey := "2fa:" + jacksonUser
	for i, tt := range jacksonChallengeCases {
		t.Run(tt.name, func(t *testing.T) {
			token := "jackson-" + strconv.Itoa(i)
			key := "2fa:challenge:" + token
			stored := jsonQuoted(t, tt.inner)
			for _, k := range []string{userCodeKey, "2fa:null"} {
				if err := client.Set(ctx, k, `"123456"`, time.Minute).Err(); err != nil {
					t.Fatal(err)
				}
			}
			if err := client.Set(ctx, key, stored, 5*time.Minute).Err(); err != nil {
				t.Fatal(err)
			}
			_, err := s.checkTwoFactor(ctx, token, "000000")
			got := rawValue(t, client, key)
			switch tt.want {
			case "session":
				wantBusinessError(t, err, MessageInvalidTwoFactorSession)
				if got != stored {
					t.Errorf("途中の記録の値 = %s, want 変わらない %s", got, stored)
				}
			case "error":
				var e *Error
				if err == nil || errors.As(err, &e) {
					t.Errorf("誤り = %v, want *Error でない誤り", err)
				}
				if got != stored {
					t.Errorf("途中の記録の値 = %s, want 変わらない %s", got, stored)
				}
			case "deleted":
				wantBusinessError(t, err, MessageInvalidTwoFactorCode)
				if got != "" {
					t.Errorf("途中の記録の値 = %s, want 消える", got)
				}
			case "limit":
				wantBusinessError(t, err, MessageTwoFactorAttemptsExceeded)
				if got != "" || keyExists(t, client, userCodeKey) {
					t.Errorf("途中の記録の値 = %s と確認のコード, want どちらも消える", got)
				}
			default:
				wantBusinessError(t, err, MessageInvalidTwoFactorCode)
				if want := jsonQuoted(t, tt.want); got != want {
					t.Errorf("途中の記録の値 = %s, want %s", got, want)
				}
				assertTTL(t, client, key, 5*time.Minute)
			}
		})
	}
}

// TestTwoFactor_ValueForms は、途中の記録と確認のコードの値そのものが JSON の文字列でないときに、
// 開発環境の Java 版と同じ結果になることを確かめる。Java 版は、値が JSON の null なら無いとみなし、
// JSON でないか、文字列でも null でもない JSON なら、予期せぬ誤りの 500 にする。
func TestTwoFactor_ValueForms(t *testing.T) {
	ctx := t.Context()
	s, client, _ := newTwoFactorService(t, nil)
	userID := uuid.New()
	codeKey := "2fa:" + userID.String()
	inner := jsonQuoted(t, `{"userId":"`+userID.String()+`","attempts":0}`)
	cases := []struct {
		name, challenge, code, want string
	}{
		{"途中の記録が null", `null`, `"123456"`, "session"},
		{"途中の記録がオブジェクト", `{"userId":"` + userID.String() + `","attempts":0}`, `"123456"`, "error"},
		{"途中の記録が JSON でない", `abc`, `"123456"`, "error"},
		{"確認のコードが null", inner, `null`, "deleted"},
		{"確認のコードが数", inner, `123456`, "error"},
		{"確認のコードが JSON でない", inner, `abc`, "error"},
	}
	for i, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			token := "value-form-" + strconv.Itoa(i)
			key := "2fa:challenge:" + token
			if err := client.Set(ctx, key, tt.challenge, time.Minute).Err(); err != nil {
				t.Fatal(err)
			}
			if err := client.Set(ctx, codeKey, tt.code, time.Minute).Err(); err != nil {
				t.Fatal(err)
			}
			// 確認のコードが数のときは、合うコードでも Java 版は 500 にする
			_, err := s.checkTwoFactor(ctx, token, "123456")
			got := rawValue(t, client, key)
			switch tt.want {
			case "session":
				wantBusinessError(t, err, MessageInvalidTwoFactorSession)
				if got != tt.challenge {
					t.Errorf("途中の記録の値 = %s, want 変わらない", got)
				}
			case "deleted":
				wantBusinessError(t, err, MessageInvalidTwoFactorCode)
				if got != "" {
					t.Errorf("途中の記録の値 = %s, want 消える", got)
				}
			default:
				var e *Error
				if err == nil || errors.As(err, &e) {
					t.Errorf("誤り = %v, want *Error でない誤り", err)
				}
				if got != tt.challenge || rawValue(t, client, codeKey) != tt.code {
					t.Error("誤りなのに値が変わった")
				}
			}
		})
	}
}

// TestTwoFactor_Errors は、乱数と SES と Redis の誤りを返すことを確かめる。
func TestTwoFactor_Errors(t *testing.T) {
	ctx := t.Context()
	t.Run("確認のコードの乱数", func(t *testing.T) {
		s, _, mailer := newTwoFactorService(t, fixedRandom(make([]byte, 3)))
		if _, err := s.issueTwoFactor(ctx, uuid.New(), "two-factor@example.com"); err == nil {
			t.Error("issueTwoFactor が誤りを返さない")
		}
		if len(mailer.got) != 0 {
			t.Error("誤りなのにメールを送った")
		}
	})
	t.Run("途中の記録の値の乱数", func(t *testing.T) {
		s, client, mailer := newTwoFactorService(t, fixedRandom([]byte{0x00, 0x01, 0xE2, 0x40, 0x01}))
		userID := uuid.New()
		if _, err := s.issueTwoFactor(ctx, userID, "two-factor@example.com"); err == nil {
			t.Error("issueTwoFactor が誤りを返さない")
		}
		if len(mailer.got) != 0 {
			t.Error("誤りなのにメールを送った")
		}
		// Java 版と同じく、置いた確認のコードは消さない
		if !keyExists(t, client, "2fa:"+userID.String()) {
			t.Error("確認のコードが置かれていない")
		}
	})
	t.Run("SES", func(t *testing.T) {
		random, wantToken := twoFactorRandom()
		s, client, mailer := newTwoFactorService(t, random)
		mailer.err = errors.New("ses down")
		userID := uuid.New()
		if _, err := s.issueTwoFactor(ctx, userID, "two-factor@example.com"); !errors.Is(err, mailer.err) {
			t.Errorf("issueTwoFactor の誤り = %v, want SES の誤りを包む", err)
		}
		if !keyExists(t, client, "2fa:"+userID.String()) || !keyExists(t, client, "2fa:challenge:"+wantToken) {
			t.Error("Java 版と違い、置いた値が消えた")
		}
	})
	t.Run("Redis", func(t *testing.T) {
		closed := redisstore.New(redisstore.Options{Addr: testRedisAddr})
		if err := closed.Close(); err != nil {
			t.Fatal(err)
		}
		s := New(Deps{Redis: closed, SES: &fakeSES{}})
		if _, err := s.issueTwoFactor(ctx, uuid.New(), "two-factor@example.com"); !errors.Is(err, redis.ErrClosed) {
			t.Errorf("issueTwoFactor の誤り = %v, want redis.ErrClosed を包む", err)
		}
		if _, err := s.checkTwoFactor(ctx, "v", "123456"); !errors.Is(err, redis.ErrClosed) {
			t.Errorf("checkTwoFactor の誤り = %v, want redis.ErrClosed を包む", err)
		}
	})
}
