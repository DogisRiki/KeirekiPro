package authctx

import (
	"context"
	"reflect"
	"testing"

	"github.com/google/uuid"
)

// With で入れた利用者の ID と役割を、UserID と Roles で取り出せることを確かめる。
func TestWithAndUserID(t *testing.T) {
	userID := uuid.MustParse("3f2504e0-4f89-11d3-9a0c-0305e82c3301")
	roles := []string{"USER", "ADMIN"}

	ctx := With(context.Background(), userID, roles)

	got, ok := UserID(ctx)
	if !ok {
		t.Fatal("UserID が false を返しました")
	}
	if got != userID {
		t.Errorf("UserID = %s, want %s", got, userID)
	}
	if gotRoles := Roles(ctx); !reflect.DeepEqual(gotRoles, roles) {
		t.Errorf("Roles = %v, want %v", gotRoles, roles)
	}
}

// 利用者を入れていない context では、UserID が false を返し、Roles が空を返すことを確かめる。
func TestUserID_MissingReturnsFalse(t *testing.T) {
	ctx := context.Background()

	got, ok := UserID(ctx)
	if ok {
		t.Errorf("UserID = %s, true; want false", got)
	}
	if got != uuid.Nil {
		t.Errorf("UserID = %s, want uuid.Nil", got)
	}
	if roles := Roles(ctx); len(roles) != 0 {
		t.Errorf("Roles = %v, want empty", roles)
	}
}
