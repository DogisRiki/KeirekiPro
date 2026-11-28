package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/middleware"
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
	// contentDisposition は、空でなければ Content-Disposition に書く。経歴書の出力の2つの操作が使う。
	contentDisposition string
	body               []byte
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

// authJSON は、v を JSON にした本文の応答を、Content-Type を application/json にして作る。
func authJSON(status int, v any, cookies ...string) authResponse {
	return authResponse{status: status, cookies: cookies, contentType: "application/json", body: marshalJSON(v)}
}

// authText は、200 で、body をそのまま本文にし、Content-Type を text/plain; charset=utf-8 にした応答を作る。
func authText(body string) authResponse {
	return authResponse{status: http.StatusOK, contentType: "text/plain; charset=utf-8", body: []byte(body)}
}

// badRequest は、400 と「入力エラーがあります。」の本文の応答を作る。
func badRequest() authResponse {
	return authJSON(http.StatusBadRequest, authErrorBody{Message: middleware.MessageBadRequest, Errors: map[string][]string{}})
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

// marshalJSON は、v を JSON にする。
func marshalJSON(v any) []byte {
	// 応答の本文の型は、JSON にするときに誤りにならない値だけを持つ
	b, _ := json.Marshal(v)
	return b
}

// write は、Set-Cookie を並べた順に書き、Location と Content-Type と Content-Disposition があれば書き、状態の番号と本文を書く。
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
	if r.contentDisposition != "" {
		h.Set("Content-Disposition", r.contentDisposition)
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
