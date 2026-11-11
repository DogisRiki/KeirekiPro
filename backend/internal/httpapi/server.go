// Package httpapi は、仕様書 api/openapi.yaml から生成したコードの経路を登録し、共通の中間処理を並べる。
package httpapi

import (
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/middleware"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/logging"
)

// ErrNotImplemented は、まだ作っていない操作が返す誤りである。HTTP の受け口は、501 と {"message":"未実装です。"} にする。
var ErrNotImplemented = errors.New("httpapi: まだ作っていない操作です")

// messageNotImplemented は、まだ作っていない操作への要求に返す文言である。
const messageNotImplemented = "未実装です。"

// queryErrorAs400Prefix は、問い合わせの値の誤りに 400 で答える経路の先頭である。Java 版は、認証の操作の
// 問い合わせの誤りに 302 か 500 を返すが、Go 版は 400 にする(design の「httpapi.New の変更」の節)。
// ほかのまとまりの spec で、問い合わせの誤りに 400 で答える操作を作るときは、その経路をここに足す。
const queryErrorAs400Prefix = "/api/auth/"

// Options は、HTTP の受け口の設定である。
type Options struct {
	// Logger は、要求のログと誤りのログを書く先である。
	Logger *slog.Logger
	// DB は、生きているかの確認で SELECT 1 を送る先である。
	DB HealthDB
	// Handlers は、仕様書の操作を受け持つ、まとまりのパッケージの処理を束ねた型である。nil なら、すべての操作に 501 を返す。
	// AuthHandlers があるときは、認証の操作には AuthHandlers が答え、ほかの操作に Handlers が答える。
	Handlers gen.StrictServerInterface
	// CORSAllowedOrigins は、CORS の処理が許す送り元である。config の App.CORSAllowedOrigins を渡す。
	CORSAllowedOrigins []string
	// Identify は、Cookie accessToken からログインの状態を読む段である。auth.Identify を渡す。nil なら、何もせずに通す。
	Identify func(http.Handler) http.Handler
	// Auth は、ログインを求める段である。auth.RequireLogin を渡す。nil なら、何もせずに通す。
	Auth func(http.Handler) http.Handler
	// AuthHandlers は、認証の操作の処理である。*auth.Service を渡す。nil なら、認証の操作も Handlers が答える。
	AuthHandlers AuthService
	// CookieSecure は、認証の操作が書く Cookie に Secure を付けるかである。config の App.CookieSecure を渡す。
	CookieSecure bool
	// APIBaseURL は、Google と GitHub から戻る先の URL の基底である。config の App.APIBaseURL を渡す。
	// 空なら、要求の Host から作る。
	APIBaseURL string
}

// routes は、認証の操作の受け口を深さ1に、ほかの操作の答えを深さ2に埋め込んだ、仕様書の操作の受け口の束である。
// Go は、同じ名前のメソッドが複数の深さにあるとき、浅い深さのメソッドを使うので、認証の操作には認証の受け口が答える。
// ほかのまとまりの spec で作る受け口も、深さ1に足す。
type routes struct {
	*authHandlers
	fallback
}

// fallback は、ほかの操作の答え(Options の Handlers か未実装の答え)を、routes の深さ2に置くための型である。
type fallback struct {
	gen.StrictServerInterface
}

// New は、仕様書の経路と生きているかの確認の経路を登録し、中間処理を、外から、パニックの受け止め、安全のヘッダ、
// 要求のログ、CORS の処理、ログインの状態の値を読む段、偽の送信の検査、ログインを求める段の順に並べた
// http.Handler を返す。登録していない経路への要求には 404 を返す。
func New(opts Options) http.Handler {
	logger := logging.Named(opts.Logger, "httpapi")
	handlers := opts.Handlers
	if handlers == nil {
		handlers = Unimplemented{}
	}
	if opts.AuthHandlers != nil {
		handlers = routes{
			authHandlers: newAuthHandlers(opts.AuthHandlers, logger, opts.CookieSecure, opts.APIBaseURL, time.Now),
			fallback:     fallback{handlers},
		}
	}

	mux := http.NewServeMux()
	strict := gen.NewStrictHandlerWithOptions(handlers, []gen.StrictMiddlewareFunc{authRequestMiddleware}, gen.StrictHTTPServerOptions{
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
		// 経路と問い合わせと Cookie とヘッダの値の形の誤りに、Java 版は 500 を返している。経路が /api/auth/ の下の
		// 問い合わせの誤り(provider が無い、code や state が2つある)は、design のとおり 400 と入力の誤りの本文にする。
		// Cookie の値は文字列のまま渡るので、Cookie の値の形の誤りはここに届かない。
		// ほかの経路は Java 版と同じ 500 にする。誤りの文は値を含むことがあるので、ログには誤りの型だけを書く
		ErrorHandlerFunc: func(w http.ResponseWriter, r *http.Request, err error) {
			if strings.HasPrefix(r.URL.Path, queryErrorAs400Prefix) {
				middleware.WriteError(w, http.StatusBadRequest, middleware.MessageBadRequest)
				return
			}
			logger.LogAttrs(r.Context(), slog.LevelError, "unexpected_exception",
				slog.Group("error", slog.String("type", fmt.Sprintf("%T", err))))
			middleware.WriteError(w, http.StatusInternalServerError, middleware.MessageUnexpected)
		},
	})
	health := healthHandler(opts.DB, logger)
	mux.Handle("GET /actuator/health", health)
	mux.Handle("GET /healthz", health)

	identify := passThrough(opts.Identify)
	requireLogin := passThrough(opts.Auth)
	return middleware.Recover(logger)(
		middleware.SecurityHeaders(
			middleware.RequestLog(logger)(
				middleware.CORS(opts.CORSAllowedOrigins)(
					identify(
						middleware.CSRF(
							requireLogin(middleware.RecordRoute(mux))))))))
}

// passThrough は、nil の中間処理を、何もせずに次の処理に渡す中間処理にする。
func passThrough(m func(http.Handler) http.Handler) func(http.Handler) http.Handler {
	if m == nil {
		return func(next http.Handler) http.Handler { return next }
	}
	return m
}
