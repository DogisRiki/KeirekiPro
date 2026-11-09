// Package httpapi は、仕様書 api/openapi.yaml から生成したコードの経路を登録し、共通の中間処理を並べる。
package httpapi

import (
	"errors"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/middleware"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/logging"
)

// ErrNotImplemented は、まだ作っていない操作が返す誤りである。HTTP の受け口は、501 と {"message":"未実装です。"} にする。
var ErrNotImplemented = errors.New("httpapi: まだ作っていない操作です")

// messageNotImplemented は、まだ作っていない操作への要求に返す文言である。
const messageNotImplemented = "未実装です。"

// Options は、HTTP の受け口の設定である。
type Options struct {
	// Logger は、要求のログと誤りのログを書く先である。
	Logger *slog.Logger
	// DB は、生きているかの確認で SELECT 1 を送る先である。
	DB HealthDB
	// Handlers は、仕様書の操作を受け持つ、まとまりのパッケージの処理を束ねた型である。nil なら、すべての操作に 501 を返す。
	Handlers gen.StrictServerInterface
	// Auth は、ログインの状態の検査の差し込み口である。認証のまとまりの spec が作る。nil なら、何もせずに通す。
	Auth func(http.Handler) http.Handler
}

// New は、仕様書の経路と生きているかの確認の経路を登録し、中間処理を、外から
// パニックの受け止め、要求のログ、偽の送信の検査、ログインの状態の検査の順に並べた http.Handler を返す。
// 登録していない経路への要求には 404 を返す。
func New(opts Options) http.Handler {
	logger := logging.Named(opts.Logger, "httpapi")
	handlers := opts.Handlers
	if handlers == nil {
		handlers = Unimplemented{}
	}

	mux := http.NewServeMux()
	strict := gen.NewStrictHandlerWithOptions(handlers, nil, gen.StrictHTTPServerOptions{
		// 要求の本文を JSON として読めないときは、Java 版の HttpMessageNotReadableException と同じ 400 にする
		RequestErrorHandlerFunc: func(w http.ResponseWriter, _ *http.Request, _ error) {
			middleware.WriteError(w, http.StatusBadRequest, middleware.MessageBadRequest)
		},
		ResponseErrorHandlerFunc: func(w http.ResponseWriter, r *http.Request, err error) {
			if errors.Is(err, ErrNotImplemented) {
				middleware.WriteMessage(w, http.StatusNotImplemented, messageNotImplemented)
				return
			}
			logger.LogAttrs(r.Context(), slog.LevelError, "unexpected_exception", logging.ErrorAttr(err, nil))
			middleware.WriteError(w, http.StatusInternalServerError, middleware.MessageUnexpected)
		},
	})
	gen.HandlerWithOptions(strict, gen.StdHTTPServerOptions{
		BaseRouter: mux,
		// 経路と問い合わせと Cookie とヘッダの値の形の誤りに、Java 版は 500 を返している。
		// 4xx に変えるかは、まとまりの spec が決めるので、ここでは Java 版と同じ 500 にする。
		// 誤りの文は値を含むことがあり、Cookie の値も含みうるので、ログには誤りの型だけを書く
		ErrorHandlerFunc: func(w http.ResponseWriter, r *http.Request, err error) {
			logger.LogAttrs(r.Context(), slog.LevelError, "unexpected_exception",
				slog.Group("error", slog.String("type", fmt.Sprintf("%T", err))))
			middleware.WriteError(w, http.StatusInternalServerError, middleware.MessageUnexpected)
		},
	})
	health := healthHandler(opts.DB, logger)
	mux.Handle("GET /actuator/health", health)
	mux.Handle("GET /healthz", health)

	auth := opts.Auth
	if auth == nil {
		auth = func(next http.Handler) http.Handler { return next }
	}
	return middleware.Recover(logger)(
		middleware.RequestLog(logger)(
			middleware.CSRF(
				auth(middleware.RecordRoute(mux)))))
}
