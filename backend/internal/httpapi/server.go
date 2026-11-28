// Package httpapi は、仕様書 api/openapi.yaml から生成したコードの経路を登録し、共通の中間処理を並べる。
package httpapi

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/middleware"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/logging"
)

// Options は、HTTP の受け口の設定である。
type Options struct {
	// Logger は、要求のログと誤りのログを書く先である。
	Logger *slog.Logger
	// DB は、生きているかの確認で SELECT 1 を送る先である。
	DB HealthDB
	// CORSAllowedOrigins は、CORS の処理が許す送り元である。config の App.CORSAllowedOrigins を渡す。
	CORSAllowedOrigins []string
	// Identify は、Cookie accessToken からログインの状態を読む段である。auth.Identify を渡す。
	Identify func(http.Handler) http.Handler
	// Auth は、ログインを求める段である。auth.RequireLogin を渡す。
	Auth func(http.Handler) http.Handler
	// AuthHandlers は、認証の13の操作の処理である。*auth.Service を渡す。
	AuthHandlers AuthService
	// UserHandlers は、利用者の7つの操作の処理である。*users.Service を渡す。
	UserHandlers UserService
	// ResumeHandlers は、マスタと経歴書の30の操作の処理である。*resume.Service を渡す。
	ResumeHandlers ResumeService
	// CookieSecure は、認証の操作が書く Cookie に Secure を付けるかである。config の App.CookieSecure を渡す。
	CookieSecure bool
	// APIBaseURL は、Google と GitHub から戻る先の URL の基底である。config の App.APIBaseURL を渡す。
	// 空なら、要求の Host から作る。
	APIBaseURL string
}

// routes は、認証の操作の受け口と利用者の操作の受け口とマスタと経歴書の操作の受け口を束ね、仕様書のすべての操作に
// 答える。3つの受け口は同じ名前のメソッドを持たない。
type routes struct {
	*authHandlers
	*userHandlers
	*resumeHandlers
}

var _ gen.StrictServerInterface = routes{}

// New は、仕様書の経路と生きているかの確認の経路を登録し、中間処理を、外から、パニックの受け止め、安全のヘッダ、
// 要求のログ、CORS の処理、ログインの状態の値を読む段、偽の送信の検査、ログインを求める段の順に並べた
// http.Handler を返す。登録していない経路への要求には 404 を返す。
func New(opts Options) http.Handler {
	logger := logging.Named(opts.Logger, "httpapi")
	handlers := routes{
		authHandlers:   newAuthHandlers(opts.AuthHandlers, logger, opts.CookieSecure, opts.APIBaseURL, time.Now),
		userHandlers:   newUserHandlers(opts.UserHandlers, opts.CookieSecure),
		resumeHandlers: newResumeHandlers(opts.ResumeHandlers, opts.CookieSecure),
	}

	mux := http.NewServeMux()
	strictMiddlewares := []gen.StrictMiddlewareFunc{authRequestMiddleware}
	strict := gen.NewStrictHandlerWithOptions(handlers, strictMiddlewares, gen.StrictHTTPServerOptions{
		// 要求の本文を JSON として読めないときは、400 と入力の誤りの本文にする
		RequestErrorHandlerFunc: func(w http.ResponseWriter, _ *http.Request, _ error) {
			middleware.WriteError(w, http.StatusBadRequest, middleware.MessageBadRequest)
		},
		ResponseErrorHandlerFunc: func(w http.ResponseWriter, r *http.Request, err error) {
			logger.LogAttrs(r.Context(), slog.LevelError, "unexpected_exception", logging.ErrorAttr(err, nil))
			middleware.WriteError(w, http.StatusInternalServerError, middleware.MessageUnexpected)
		},
	})
	gen.HandlerWithOptions(strict, gen.StdHTTPServerOptions{
		BaseRouter:       mux,
		ErrorHandlerFunc: paramErrorHandler,
	})
	health := healthHandler(opts.DB, logger)
	mux.Handle("GET /actuator/health", health)
	mux.Handle("GET /healthz", health)

	return middleware.Recover(logger)(
		middleware.SecurityHeaders(
			middleware.RequestLog(logger)(
				middleware.CORS(opts.CORSAllowedOrigins)(
					opts.Identify(
						middleware.CSRF(
							opts.Auth(limitUpdateUserInfoBody(middleware.RecordRoute(mux)))))))))
}

// paramErrorHandler は、問い合わせの値の形の誤り(provider が無い、code や state が2つある)に、400 と入力の誤りの
// 本文で答える。経路と Cookie とヘッダの値は文字列のまま渡るので、これらの値の形の誤りはここに届かない。
func paramErrorHandler(w http.ResponseWriter, _ *http.Request, _ error) {
	middleware.WriteError(w, http.StatusBadRequest, middleware.MessageBadRequest)
}
