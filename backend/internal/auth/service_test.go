package auth

import (
	"net/http"
	"testing"
	"time"
)

// TestNew_FillsDefaults は、時刻と乱数と HTTP のクライアントを渡さないとき、New が本番の値を入れ、
// HTTP のクライアントの打ち切りを、設計のとおり10秒にすることを確かめる。
func TestNew_FillsDefaults(t *testing.T) {
	s := New(Deps{})
	if s.deps.HTTPClient == nil || s.deps.HTTPClient.Timeout != 10*time.Second {
		t.Errorf("HTTPClient = %+v, want 打ち切りが10秒のクライアント", s.deps.HTTPClient)
	}
	if s.deps.Now == nil {
		t.Error("Now が nil のまま")
	}
	if s.deps.Random == nil {
		t.Fatal("Random が nil のまま")
	}
	if _, err := randomToken(s.deps.Random); err != nil {
		t.Errorf("既定の Random で乱数を読めない: %v", err)
	}
}

// TestNew_KeepsGivenDeps は、渡した時刻と乱数と HTTP のクライアントを、New が置き換えないことを確かめる。
func TestNew_KeepsGivenDeps(t *testing.T) {
	fixed := time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC)
	client := &http.Client{Timeout: time.Second}
	s := New(Deps{
		HTTPClient: client,
		Now:        func() time.Time { return fixed },
		Random:     fixedRandom([]byte{0, 0, 0, 7}),
	})
	if s.deps.HTTPClient != client {
		t.Error("渡した HTTPClient が置き換えられた")
	}
	if got := s.deps.Now(); !got.Equal(fixed) {
		t.Errorf("Now() = %v, want %v", got, fixed)
	}
	if got, err := randomCode(s.deps.Random); err != nil || got != "000007" {
		t.Errorf("randomCode(渡した Random) = %q, %v, want %q", got, err, "000007")
	}
}
