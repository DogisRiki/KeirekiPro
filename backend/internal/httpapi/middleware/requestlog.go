package middleware

import (
	"context"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/logging"
)

// routeKey は、経路の型を書き込む先を、要求の context に置くときの鍵である。
type routeKey struct{}

// RequestLog は、要求ごとに、メソッドと経路の型とステータスとかかった時間を1行のログに書く。
// Cookie と Authorization と要求の本文は、logging.Request が受け取らないので、ログに書かない。
// 経路の型は、RecordRoute が、経路の登録の表で当たった型を書き込む。後ろの処理がパニックを起こしたときは、ステータスを 500 として書く。
func RequestLog(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			route := new(string)
			recorder := &statusRecorder{ResponseWriter: w}
			panicked := true
			defer func() {
				status := recorder.status
				switch {
				case panicked:
					status = http.StatusInternalServerError
				case status == 0:
					// 何も書かなかった要求には、net/http が 200 を返す
					status = http.StatusOK
				}
				logging.Request(r.Context(), logger, r.Method, *route, status, time.Since(start))
			}()
			next.ServeHTTP(recorder, r.WithContext(context.WithValue(r.Context(), routeKey{}, route)))
			panicked = false
		})
	}
}

// RecordRoute は、経路の登録の表 mux が要求に当てた経路の型を、RequestLog に渡す。
// RecordRoute は、mux のすぐ外に置く。経路の型は、メソッドを除いた形(例: /api/resumes/{resumeId})にする。
// どの経路の型にも当たらなかった要求では、空にする。
// mux は、経路の型を決めてから処理を呼ぶときに r.Pattern に書くので、処理がパニックを起こしたときも、defer で経路の型を渡す。
func RecordRoute(mux http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			route, ok := r.Context().Value(routeKey{}).(*string)
			if !ok {
				return
			}
			pattern := r.Pattern
			if _, path, found := strings.Cut(pattern, " "); found {
				pattern = path
			}
			*route = pattern
		}()
		mux.ServeHTTP(w, r)
	})
}

// statusRecorder は、書いたステータスを覚える。ヘッダを書かずに本文を書いたときは、net/http と同じく 200 とする。
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(status int) {
	if s.status == 0 {
		s.status = status
	}
	s.ResponseWriter.WriteHeader(status)
}

func (s *statusRecorder) Write(b []byte) (int, error) {
	if s.status == 0 {
		s.status = http.StatusOK
	}
	return s.ResponseWriter.Write(b)
}

// Unwrap は、http.ResponseController が元の書き手の機能を使えるようにする。
func (s *statusRecorder) Unwrap() http.ResponseWriter {
	return s.ResponseWriter
}
