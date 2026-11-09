package httpapi_test

import (
	"context"
	"errors"
	"net/http"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
)

// fakeDB は、受けた SQL を記録し、決めた誤りを返す。
type fakeDB struct {
	err  error
	sqls []string
}

func (f *fakeDB) Exec(_ context.Context, sql string, _ ...any) (pgconn.CommandTag, error) {
	f.sqls = append(f.sqls, sql)
	return pgconn.CommandTag{}, f.err
}

// 生きているかの確認が、データベースに SELECT 1 を送り、通れば UP、通らなければ DOWN を返すことを確かめる。
func TestHealth_UpAndDown(t *testing.T) {
	for _, path := range []string{"/actuator/health", "/healthz"} {
		t.Run(path+" UP", func(t *testing.T) {
			db := &fakeDB{}
			handler, _ := server(nil, db)
			rec := send(handler, http.MethodGet, path, "")
			assertBody(t, rec, http.StatusOK, "application/json", `{"status":"UP"}`)
			if len(db.sqls) != 1 || db.sqls[0] != "SELECT 1" {
				t.Errorf("送った SQL = %q, want [SELECT 1]", db.sqls)
			}
		})
		t.Run(path+" DOWN", func(t *testing.T) {
			db := &fakeDB{err: errors.New("つなげません")}
			handler, logs := server(nil, db)
			rec := send(handler, http.MethodGet, path, "")
			assertBody(t, rec, http.StatusServiceUnavailable, "application/json", `{"status":"DOWN"}`)
			line := requestLog(t, logs)
			if route, _ := line["http"].(map[string]any)["route"].(string); route != path {
				t.Errorf("経路の型 = %q, want %q", route, path)
			}
		})
	}
	t.Run("POST は受け付けない", func(t *testing.T) {
		handler, _ := server(nil, &fakeDB{})
		if rec := send(handler, http.MethodPost, "/healthz", ""); rec.Code != http.StatusMethodNotAllowed {
			t.Errorf("ステータス = %d, want 405", rec.Code)
		}
	})
}
