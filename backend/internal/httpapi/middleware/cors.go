package middleware

import (
	"net"
	"net/http"
	"net/url"
	"slices"
	"strings"
)

// corsAllowedMethods は、許す送り元からの要求に許す6つのメソッドである。
var corsAllowedMethods = []string{
	http.MethodGet, http.MethodPost, http.MethodPut, http.MethodDelete, http.MethodPatch, http.MethodOptions,
}

const (
	// corsVary は、すべての応答に付ける Vary の値である。答えが Origin と、プリフライトの求めるメソッドとヘッダで変わるためである。
	corsVary = "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
	// corsExposeHeaders は、画面の JavaScript が読んでよい応答のヘッダである。
	corsExposeHeaders = "Content-Disposition, X-Request-Id"
)

// CORS は、allowedOrigins の送り元からの要求だけを許す中間処理を作る。allowedOrigins は、config の CORS の許す送り元である。
//
//   - すべての応答に Vary を付ける
//   - Origin が無い要求と、Origin が要求の宛先と同じ送り元の要求は、CORS の要求でないので、何もせずに次の処理に渡す
//   - Origin が許す送り元に無い要求には、403 と「アクセス権限がありません。」で答える
//   - 許す送り元からのプリフライトは、求めるメソッドが6つのメソッドのどれかなら 200 で答え、どれでもなければ 403 で答える。どちらも次の処理に渡さない
//   - 許す送り元からのプリフライトでない要求は、メソッドが6つのメソッドのどれかなら、ヘッダを付けて次の処理に渡し、どれでもなければ 403 で答える
func CORS(allowedOrigins []string) func(http.Handler) http.Handler {
	allowed := slices.Clone(allowedOrigins)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			h := w.Header()
			h.Add("Vary", corsVary)
			origin := r.Header.Get("Origin")
			if origin == "" || sameOrigin(r, origin) {
				next.ServeHTTP(w, r)
				return
			}
			method := r.Method
			if isPreflight(r) {
				method = r.Header.Get("Access-Control-Request-Method")
			}
			if !slices.Contains(allowed, origin) || !slices.Contains(corsAllowedMethods, method) {
				WriteMessage(w, http.StatusForbidden, MessageForbidden)
				return
			}
			h.Set("Access-Control-Allow-Origin", origin)
			h.Set("Access-Control-Allow-Credentials", "true")
			if isPreflight(r) {
				h.Set("Access-Control-Allow-Methods", strings.Join(corsAllowedMethods, ","))
				if requested := r.Header.Get("Access-Control-Request-Headers"); requested != "" {
					h.Set("Access-Control-Allow-Headers", requested)
				}
				w.WriteHeader(http.StatusOK)
				return
			}
			h.Set("Access-Control-Expose-Headers", corsExposeHeaders)
			next.ServeHTTP(w, r)
		})
	}
}

// isPreflight は、要求がプリフライトか(OPTIONS で、Access-Control-Request-Method を持つか)を返す。
func isPreflight(r *http.Request) bool {
	return r.Method == http.MethodOptions && r.Header.Get("Access-Control-Request-Method") != ""
}

// sameOrigin は、Origin が要求の宛先と同じ送り元(方式と名前とポート)かを返す。
// 要求の方式は、TLS で受けたかで決める。本番では ALB が TLS を終えるので、Go 版には http の要求に見える。
func sameOrigin(r *http.Request, origin string) bool {
	u, err := url.Parse(origin)
	if err != nil || u.Host == "" {
		return false
	}
	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}
	if !strings.EqualFold(u.Scheme, scheme) {
		return false
	}
	originHost, originPort := splitHostPort(u.Host, scheme)
	reqHost, reqPort := splitHostPort(r.Host, scheme)
	return strings.EqualFold(originHost, reqHost) && originPort == reqPort
}

// splitHostPort は、「名前:ポート」を名前とポートに分ける。ポートが無ければ、方式の既定のポートにする。
func splitHostPort(hostport, scheme string) (string, string) {
	host, port, err := net.SplitHostPort(hostport)
	if err != nil {
		host, port = hostport, ""
	}
	if port == "" {
		port = "80"
		if scheme == "https" {
			port = "443"
		}
	}
	return host, port
}
