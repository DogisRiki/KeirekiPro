package middleware

import (
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"runtime/debug"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/logging"
)

// Recover は、後ろの処理のパニックを受け止め、パニックが起きたときのスタックをログに書き、
// Java 版の想定外の誤りと同じ 500 と {"message":"予期せぬエラーが発生しました。","errors":{}} を返す。
// 応答をすでに書き始めていたときは、ログだけを書く。
// http.ErrAbortHandler のパニックは、net/http が応答を打ち切るための合図なので、受け止めずに投げ直す。
func Recover(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			tracker := &headerTracker{ResponseWriter: w}
			defer func() {
				recovered := recover()
				if recovered == nil {
					return
				}
				if err, ok := recovered.(error); ok && errors.Is(err, http.ErrAbortHandler) {
					panic(recovered)
				}
				logger.LogAttrs(r.Context(), slog.LevelError, "unexpected_exception",
					logging.ErrorAttr(fmt.Errorf("panic: %v", recovered), debug.Stack()))
				if !tracker.wroteHeader {
					WriteError(w, http.StatusInternalServerError, MessageUnexpected)
				}
			}()
			next.ServeHTTP(tracker, r)
		})
	}
}

// headerTracker は、応答のヘッダをすでに書いたかを覚える。
type headerTracker struct {
	http.ResponseWriter
	wroteHeader bool
}

func (t *headerTracker) WriteHeader(status int) {
	t.wroteHeader = true
	t.ResponseWriter.WriteHeader(status)
}

func (t *headerTracker) Write(b []byte) (int, error) {
	t.wroteHeader = true
	return t.ResponseWriter.Write(b)
}

// Unwrap は、http.ResponseController が元の書き手の機能を使えるようにする。
func (t *headerTracker) Unwrap() http.ResponseWriter {
	return t.ResponseWriter
}
