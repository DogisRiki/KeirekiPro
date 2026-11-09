package httpapi

import (
	"context"
	"log/slog"
	"net/http"

	"github.com/jackc/pgx/v5/pgconn"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/logging"
)

// HealthDB は、生きているかの確認で使う、データベースへの問い合わせである。*pgxpool.Pool が満たす。
type HealthDB interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

// healthHandler は、データベースに SELECT 1 を送り、通れば 200 と {"status":"UP"} を、
// 通らなければ 503 と {"status":"DOWN"} を返す。Java 版の /actuator/health と同じ本文である。
func healthHandler(db HealthDB, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if _, err := db.Exec(r.Context(), "SELECT 1"); err != nil {
			logger.LogAttrs(r.Context(), slog.LevelWarn, "health_check_failed", logging.ErrorAttr(err, nil))
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"status":"DOWN"}`))
			return
		}
		_, _ = w.Write([]byte(`{"status":"UP"}`))
	})
}
