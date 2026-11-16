package resume

import (
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
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
	fixed := time.Date(2026, 11, 14, 10, 23, 45, 341237480, time.UTC)
	// 接続しない接続の束を渡す。New は接続の束を使わずに持つだけである
	pool := &pgxpool.Pool{}
	s := New(Deps{Pool: pool, Now: func() time.Time { return fixed }})
	if got := s.deps.Now(); !got.Equal(fixed) {
		t.Errorf("Now() = %v, want %v", got, fixed)
	}
	if s.deps.Pool != pool {
		t.Errorf("Pool = %p, want %p", s.deps.Pool, pool)
	}
}
