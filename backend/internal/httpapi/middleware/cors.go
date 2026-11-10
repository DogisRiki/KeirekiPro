package middleware

import (
	"net"
	"net/http"
	"net/url"
	"slices"
	"strings"
)

// corsAllowedMethods は、Java 版の CORS の設定が許す6つのメソッドである。
var corsAllowedMethods = []string{
	http.MethodGet, http.MethodPost, http.MethodPut, http.MethodDelete, http.MethodPatch, http.MethodOptions,
}

// corsVary は、Java 版の CORS の処理がすべての応答に付ける Vary の値である。Java 版と同じく、値ごとに別の行で付ける。
var corsVary = []string{"Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers"}

const (
	// corsExposeHeaders は、画面の JavaScript が読んでよい応答のヘッダである。
	corsExposeHeaders = "Content-Disposition, X-Request-Id"
	// corsRejected は、Java 版の CORS の処理が断るときに返す本文である。
	corsRejected = "Invalid CORS request"
)

// CORS は、Java 版の SecurityConfig の CORS の設定と同じ応答を返す中間処理を作る。allowedOrigins は、config の CORS の許す送り元である。
//
//   - すべての応答に Vary を付ける
//   - Origin が無い要求と、Origin が要求の宛先と同じ送り元の要求は、CORS の要求でないので、何もせずに次の処理に渡す
//   - Origin が許す送り元に無い要求には、403 と本文 Invalid CORS request を返す
//   - 許す送り元からのプリフライトは、求めるメソッドが6つのメソッドのどれかなら、Java 版と同じく Access-Control-Expose-Headers も付けて 200 を返し、どれでもなければ 403 を返す。どちらも次の処理に渡さない
//   - 許す送り元からのプリフライトでない要求は、メソッドが6つのメソッドのどれかなら、ヘッダを付けて次の処理に渡し、どれでもなければ 403 を返す
func CORS(allowedOrigins []string) func(http.Handler) http.Handler {
	allowed := slices.Clone(allowedOrigins)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			for _, value := range corsVary {
				w.Header().Add("Vary", value)
			}
			origin := r.Header.Get("Origin")
			if origin == "" || sameOrigin(r, origin) {
				next.ServeHTTP(w, r)
				return
			}
			if !slices.Contains(allowed, origin) {
				rejectCORS(w)
				return
			}
			if isPreflight(r) {
				if !slices.Contains(corsAllowedMethods, r.Header.Get("Access-Control-Request-Method")) {
					rejectCORS(w)
					return
				}
				h := w.Header()
				h.Set("Access-Control-Allow-Origin", origin)
				h.Set("Access-Control-Allow-Methods", strings.Join(corsAllowedMethods, ","))
				if requested := requestedHeaders(r); len(requested) > 0 {
					h.Set("Access-Control-Allow-Headers", strings.Join(requested, ", "))
				}
				h.Set("Access-Control-Expose-Headers", corsExposeHeaders)
				h.Set("Access-Control-Allow-Credentials", "true")
				w.WriteHeader(http.StatusOK)
				return
			}
			if !slices.Contains(corsAllowedMethods, r.Method) {
				rejectCORS(w)
				return
			}
			h := w.Header()
			h.Set("Access-Control-Allow-Origin", origin)
			h.Set("Access-Control-Expose-Headers", corsExposeHeaders)
			h.Set("Access-Control-Allow-Credentials", "true")
			next.ServeHTTP(w, r)
		})
	}
}

// rejectCORS は、Java 版の CORS の処理と同じく、Content-Type を付けずに、403 と本文 Invalid CORS request を返す。
// net/http は、Content-Type の無い応答に本文から推した Content-Type を付けるので、値を nil にしてそれを止める。
func rejectCORS(w http.ResponseWriter) {
	w.Header()["Content-Type"] = nil
	w.WriteHeader(http.StatusForbidden)
	// 書き込みの誤りは、利用者との接続が切れたときに起きる。応答を書き直す先が無いので、ここでは扱わない
	_, _ = w.Write([]byte(corsRejected))
}

// requestedHeaders は、プリフライトの Access-Control-Request-Headers を、コンマで分けて前後の空白を除いた名前の並びにする。
// Java 版は、名前を「, 」でつなぎ直して Access-Control-Allow-Headers に返すので、Go 版も同じ形で返すために分ける。
func requestedHeaders(r *http.Request) []string {
	var names []string
	for _, value := range r.Header.Values("Access-Control-Request-Headers") {
		for name := range strings.SplitSeq(value, ",") {
			if name = strings.TrimSpace(name); name != "" {
				names = append(names, name)
			}
		}
	}
	return names
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
