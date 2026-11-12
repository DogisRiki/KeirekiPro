package middleware

import "net/http"

// securityHeaders は、Java 版の Spring Security が既定で応答に置く6つのヘッダである。
var securityHeaders = [...]struct{ name, value string }{
	{"Cache-Control", "no-cache, no-store, max-age=0, must-revalidate"},
	{"Pragma", "no-cache"},
	{"Expires", "0"},
	{"X-Content-Type-Options", "nosniff"},
	{"X-Frame-Options", "DENY"},
	{"X-XSS-Protection", "0"},
}

// SecurityHeaders は、次の処理に渡す前に、Java 版と同じ6つのヘッダを応答に置く。
// 次の処理に渡す前に置くので、次の処理がヘッダを上書きしたときは、上書きした値が残る。
// また、外側の Recover が返すパニックの 500 にも、6つのヘッダが付く。
func SecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := w.Header()
		for _, h := range securityHeaders {
			header.Set(h.name, h.value)
		}
		next.ServeHTTP(w, r)
	})
}
