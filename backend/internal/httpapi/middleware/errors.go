// Package middleware は、HTTP の受け口のすべての要求に、まとまりの処理より前に動く共通の処理を置く。
// 置くのは、パニックの受け止め、要求のログ、偽の送信の検査と、Java 版と同じエラーの応答の形である。
package middleware

import (
	"encoding/json"
	"net/http"
)

// Java 版の AppExceptionHandler と SecurityConfig が返す文言である。
const (
	// MessageBadRequest は、要求の本文を JSON として読めないときの文言である。
	MessageBadRequest = "入力エラーがあります。"
	// MessageUnexpected は、想定外の誤りのときの文言である。
	MessageUnexpected = "予期せぬエラーが発生しました。"
	// MessageForbidden は、偽の送信の検査に通らないときの文言である。
	MessageForbidden = "アクセス権限がありません。"
)

// errorBody は、Java 版の ErrorResponse と同じ {message, errors} の形である。
type errorBody struct {
	Message string              `json:"message"`
	Errors  map[string][]string `json:"errors"`
}

// WriteError は、Java 版と同じ {message, errors} の形の本文を、errors を空のオブジェクトにして書く。
func WriteError(w http.ResponseWriter, status int, message string) {
	// 文字列と空の map だけの値は、JSON にするときに誤りにならない
	body, _ := json.Marshal(errorBody{Message: message, Errors: map[string][]string{}})
	write(w, status, "application/json", body)
}

// messageBody は、errors を持たない {message} の形である。
type messageBody struct {
	Message string `json:"message"`
}

// WriteMessage は、errors を持たない {message} の形の本文を書く。
func WriteMessage(w http.ResponseWriter, status int, message string) {
	writeMessage(w, status, "application/json", message)
}

func writeMessage(w http.ResponseWriter, status int, contentType, message string) {
	// 文字列だけの値は、JSON にするときに誤りにならない
	body, _ := json.Marshal(messageBody{Message: message})
	write(w, status, contentType, body)
}

// write は、Content-Type と status を付けて本文を書く。
func write(w http.ResponseWriter, status int, contentType string, body []byte) {
	w.Header().Set("Content-Type", contentType)
	w.WriteHeader(status)
	// 書き込みの誤りは、利用者との接続が切れたときに起きる。応答を書き直す先が無いので、ここでは扱わない
	_, _ = w.Write(body)
}
