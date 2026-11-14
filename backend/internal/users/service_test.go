package users

import (
	"testing"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// TestNew_DefaultsNowToTimeNow は、時刻の関数を渡さないとき、New が今の時刻を返す関数を使うことを確かめる。
func TestNew_DefaultsNowToTimeNow(t *testing.T) {
	s := New(Deps{})
	if s.deps.Now == nil {
		t.Fatal("New(Deps{}) の Now が nil のまま")
	}
	before := time.Now()
	got := s.deps.Now()
	after := time.Now()
	if got.Before(before) || got.After(after) {
		t.Errorf("Now() = %v, want %v から %v の間", got, before, after)
	}
}

// TestNew_KeepsGivenDeps は、渡した部品を New がそのまま持つことを確かめる。
func TestNew_KeepsGivenDeps(t *testing.T) {
	fixed := time.Date(2026, 11, 13, 9, 0, 0, 0, time.UTC)
	authService := auth.New(auth.Deps{})
	s := New(Deps{
		Auth:               authService,
		Bucket:             "keirekipro-storage",
		RewritePresignHost: true,
		AWSEndpoint:        "http://localstack:4566",
		Now:                func() time.Time { return fixed },
	})
	if got := s.deps.Now(); !got.Equal(fixed) {
		t.Errorf("Now() = %v, want %v", got, fixed)
	}
	if s.deps.Auth != authService {
		t.Errorf("Auth = %p, want %p", s.deps.Auth, authService)
	}
	if s.deps.Bucket != "keirekipro-storage" {
		t.Errorf("Bucket = %q, want %q", s.deps.Bucket, "keirekipro-storage")
	}
	if !s.deps.RewritePresignHost {
		t.Error("RewritePresignHost = false, want true")
	}
	if s.deps.AWSEndpoint != "http://localstack:4566" {
		t.Errorf("AWSEndpoint = %q, want %q", s.deps.AWSEndpoint, "http://localstack:4566")
	}
}
