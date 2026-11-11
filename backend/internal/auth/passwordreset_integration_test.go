package auth

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

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
