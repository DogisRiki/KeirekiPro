package httpapi

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
)

// authResponse は、認証の操作の応答である。生成した応答の型は Set-Cookie を1つしか書けないので、Java 版と同じく
// Set-Cookie を2つ以上書く認証の操作は、この型で答える。この型は、認証の13の操作の応答のインタフェースを満たす。
type authResponse struct {
	status int
	// cookies は、Set-Cookie の値である。この順に書く。
	cookies []string
	// location は、空でなければ Location に書く。
	location string
	// contentType は、空でなければ Content-Type に書く。
	contentType string
	body        []byte
}

var (
	_ gen.VerifyTwoFactorAuthResponseObject             = authResponse{}
	_ gen.ResendEmailVerificationResponseObject         = authResponse{}
	_ gen.ResendEmailVerificationForLoginResponseObject = authResponse{}
	_ gen.VerifyEmailResponseObject                     = authResponse{}
	_ gen.LoginResponseObject                           = authResponse{}
	_ gen.LogoutResponseObject                          = authResponse{}
	_ gen.StartOidcAuthorizationResponseObject          = authResponse{}
	_ gen.HandleOidcCallbackResponseObject              = authResponse{}
	_ gen.ResetPasswordResponseObject                   = authResponse{}
	_ gen.RequestPasswordResetResponseObject            = authResponse{}
	_ gen.VerifyPasswordResetTokenResponseObject        = authResponse{}
	_ gen.RegisterUserResponseObject                    = authResponse{}
	_ gen.RefreshTokenResponseObject                    = authResponse{}
)

// authNoBody は、本文の無い応答を作る。
func authNoBody(status int, cookies ...string) authResponse {
	return authResponse{status: status, cookies: cookies}
}

// authJSON は、v を Java 版の Jackson と同じく書いた本文の応答を、Content-Type を application/json にして作る。
func authJSON(status int, v any, cookies ...string) authResponse {
	return authResponse{status: status, cookies: cookies, contentType: "application/json", body: jacksonJSON(v)}
}

// authText は、200 で、body をそのまま本文にした応答を作る。
func authText(contentType, body string) authResponse {
	return authResponse{status: http.StatusOK, contentType: contentType, body: []byte(body)}
}

// authRedirect は、location に移る 302 の応答を、本文を書かずに作る。
func authRedirect(location string, cookies ...string) authResponse {
	return authResponse{status: http.StatusFound, cookies: cookies, location: location}
}

// verifyEmailBody は、Java 版の VerifyEmailResponse と同じ {result, passwordResetToken} の形である。
// passwordResetToken は、値が無いときも null として書く。
type verifyEmailBody struct {
	Result             string  `json:"result"`
	PasswordResetToken *string `json:"passwordResetToken"`
}

// authErrorBody は、Java 版の ErrorResponse と同じ {message, errors} の形である。
type authErrorBody struct {
	Message string              `json:"message"`
	Errors  map[string][]string `json:"errors"`
}

// authEmailNotVerifiedBody は、Java 版の EmailNotVerifiedErrorResponse と同じ {message, errors, kind} の形である。
type authEmailNotVerifiedBody struct {
	Message string              `json:"message"`
	Errors  map[string][]string `json:"errors"`
	Kind    auth.EmailKind      `json:"kind"`
}

// authErrorResponse は、err が *auth.Error を含めば、Java 版の AppExceptionHandler と同じ状態の番号と本文と Cookie の
// 応答を作り、真を返す。Kind があれば {message, errors, kind}、なければ {message, errors} を書く。ClearSession が
// 真なら、Java 版と同じく、accessToken と refreshToken を消す Cookie をこの順に書く。*auth.Error を含まなければ偽を返す。
func authErrorResponse(err error, secure bool) (authResponse, bool) {
	var e *auth.Error
	if !errors.As(err, &e) {
		return authResponse{}, false
	}
	fields := e.Errors
	if fields == nil {
		fields = map[string][]string{}
	}
	var body any = authErrorBody{Message: e.Message, Errors: fields}
	if e.Kind != "" {
		body = authEmailNotVerifiedBody{Message: e.Message, Errors: fields, Kind: e.Kind}
	}
	var cookies []string
	if e.ClearSession {
		cookies = []string{auth.DeleteCookie("accessToken", "/", secure), auth.DeleteCookie("refreshToken", "/", secure)}
	}
	return authJSON(e.Status, body, cookies...), true
}

// jacksonJSON は、v を、Java 版の Jackson と同じく < > & を逃がさずに、末尾の改行を付けずに JSON にする。
// 認証の応答の本文に入る文字列は、決まった文言と項目の名前と、base64url の値だけである。Go と Jackson で書き方の
// 違う U+2028、U+2029、U+10000 以上の文字は入らないので、ほかの違いは直さない。
func jacksonJSON(v any) []byte {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	// 文字列と文字列の束と文字列への参照だけの値は、JSON にするときに誤りにならない
	_ = enc.Encode(v)
	return bytes.TrimSuffix(buf.Bytes(), []byte("\n"))
}

// write は、Set-Cookie を並べた順に書き、Location と Content-Type があれば書き、状態の番号と本文を書く。
func (r authResponse) write(w http.ResponseWriter) error {
	h := w.Header()
	for _, c := range r.cookies {
		h.Add("Set-Cookie", c)
	}
	if r.location != "" {
		h.Set("Location", r.location)
	}
	if r.contentType != "" {
		h.Set("Content-Type", r.contentType)
	}
	w.WriteHeader(r.status)
	if len(r.body) == 0 {
		return nil
	}
	_, err := w.Write(r.body)
	return err
}

// VisitVerifyTwoFactorAuthResponse は、応答を書く。
func (r authResponse) VisitVerifyTwoFactorAuthResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitResendEmailVerificationResponse は、応答を書く。
func (r authResponse) VisitResendEmailVerificationResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitResendEmailVerificationForLoginResponse は、応答を書く。
func (r authResponse) VisitResendEmailVerificationForLoginResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitVerifyEmailResponse は、応答を書く。
func (r authResponse) VisitVerifyEmailResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitLoginResponse は、応答を書く。
func (r authResponse) VisitLoginResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitLogoutResponse は、応答を書く。
func (r authResponse) VisitLogoutResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitStartOidcAuthorizationResponse は、応答を書く。
func (r authResponse) VisitStartOidcAuthorizationResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitHandleOidcCallbackResponse は、応答を書く。
func (r authResponse) VisitHandleOidcCallbackResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitResetPasswordResponse は、応答を書く。
func (r authResponse) VisitResetPasswordResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitRequestPasswordResetResponse は、応答を書く。
func (r authResponse) VisitRequestPasswordResetResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitVerifyPasswordResetTokenResponse は、応答を書く。
func (r authResponse) VisitVerifyPasswordResetTokenResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitRegisterUserResponse は、応答を書く。
func (r authResponse) VisitRegisterUserResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitRefreshTokenResponse は、応答を書く。
func (r authResponse) VisitRefreshTokenResponse(w http.ResponseWriter) error { return r.write(w) }
