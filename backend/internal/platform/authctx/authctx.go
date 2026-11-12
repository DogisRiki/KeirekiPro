// Package authctx は、ログインした利用者の ID と役割を context.Context に入れ、取り出す。
// ほかのまとまりのパッケージは、このパッケージを読んで、ログインした利用者の ID を得る。
// このパッケージは、ログインの状態の値を確かめない。確かめるのは internal/auth の Identify だけである。
package authctx

import (
	"context"

	"github.com/google/uuid"
)

// userKey は、context に利用者を入れるときのキーの型である。ほかのパッケージのキーと重ならないように、外に出さない型にする。
type userKey struct{}

// user は、context に入れる、ログインした利用者である。
type user struct {
	id    uuid.UUID
	roles []string
}

// With は、ログインした利用者の ID と役割を入れた context を返す。
// 呼び出し元があとで roles を書き換えても context の中身が変わらないように、役割の写しを入れる。
func With(ctx context.Context, userID uuid.UUID, roles []string) context.Context {
	return context.WithValue(ctx, userKey{}, user{id: userID, roles: append([]string(nil), roles...)})
}

// UserID は、context からログインした利用者の ID を取り出す。利用者が入っていなければ、uuid.Nil と false を返す。
func UserID(ctx context.Context) (uuid.UUID, bool) {
	u, ok := ctx.Value(userKey{}).(user)
	if !ok {
		return uuid.Nil, false
	}
	return u.id, true
}

// Roles は、context からログインした利用者の役割を取り出す。利用者が入っていなければ、nil を返す。
// 呼び出し元が戻り値を書き換えても context の中身が変わらないように、写しを返す。
func Roles(ctx context.Context) []string {
	u, ok := ctx.Value(userKey{}).(user)
	if !ok {
		return nil
	}
	return append([]string(nil), u.roles...)
}
