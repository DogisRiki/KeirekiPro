package httpapi

import (
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// wantResponse は、応答の状態の番号、Set-Cookie の並び、Location、Content-Type、本文の期待である。
type wantResponse struct {
	status      int
	cookies     []string
	location    string
	contentType string
	body        string
}

// recordResponse は、visit で書いた応答を読む。
func recordResponse(t *testing.T, visit func(http.ResponseWriter) error) wantResponse {
	t.Helper()
	rec := httptest.NewRecorder()
	if err := visit(rec); err != nil {
		t.Fatalf("応答を書けない: %v", err)
	}
	res := rec.Result()
	t.Cleanup(func() { _ = res.Body.Close() })
	return wantResponse{
		status:      res.StatusCode,
		cookies:     res.Header.Values("Set-Cookie"),
		location:    res.Header.Get("Location"),
		contentType: res.Header.Get("Content-Type"),
		body:        rec.Body.String(),
	}
}

// checkResponse は、got が want と同じかを確かめる。
func checkResponse(t *testing.T, name string, got, want wantResponse) {
	t.Helper()
	if !reflect.DeepEqual(got, want) {
		t.Errorf("%s の応答 = %+v, want %+v", name, got, want)
	}
}

// visitors は、認証の13の操作の応答のインタフェースのメソッドで、r を書く関数を返す。
func visitors(r authResponse) map[string]func(http.ResponseWriter) error {
	return map[string]func(http.ResponseWriter) error{
		"VerifyTwoFactorAuth":             r.VisitVerifyTwoFactorAuthResponse,
		"ResendEmailVerification":         r.VisitResendEmailVerificationResponse,
		"ResendEmailVerificationForLogin": r.VisitResendEmailVerificationForLoginResponse,
		"VerifyEmail":                     r.VisitVerifyEmailResponse,
		"Login":                           r.VisitLoginResponse,
		"Logout":                          r.VisitLogoutResponse,
		"StartOidcAuthorization":          r.VisitStartOidcAuthorizationResponse,
		"HandleOidcCallback":              r.VisitHandleOidcCallbackResponse,
		"ResetPassword":                   r.VisitResetPasswordResponse,
		"RequestPasswordReset":            r.VisitRequestPasswordResetResponse,
		"VerifyPasswordResetToken":        r.VisitVerifyPasswordResetTokenResponse,
		"RegisterUser":                    r.VisitRegisterUserResponse,
		"RefreshToken":                    r.VisitRefreshTokenResponse,
	}
}

// TestAuthResponses_StatusBodyCookies は、認証の操作の応答の型が、Java 版と同じく、状態の番号と、Set-Cookie を
// 渡した順に2つ以上と、Location と、Content-Type と、本文を書くことを確かめる(要件1.1)。生成した応答の型は
// Set-Cookie を1つしか書けないので、この型を使う。13の操作のどのメソッドで書いても同じ応答になる。
func TestAuthResponses_StatusBodyCookies(t *testing.T) {
	access := auth.SessionCookie("accessToken", "a.b.c", false)
	refresh := auth.SessionCookie("refreshToken", "r", false)
	deleteChallenge := auth.DeleteCookie(auth.ChallengeCookieName, auth.ChallengeCookiePath, false)
	token := "reset-value"
	cases := []struct {
		name string
		r    authResponse
		want wantResponse
	}{
		{
			name: "本文の無い 200 と Cookie 3つ",
			r:    authNoBody(http.StatusOK, access, refresh, deleteChallenge),
			want: wantResponse{status: 200, cookies: []string{access, refresh, deleteChallenge}, body: ""},
		},
		{
			name: "本文も Cookie も無い 204",
			r:    authNoBody(http.StatusNoContent),
			want: wantResponse{status: 204, body: ""},
		},
		{
			name: "本文の無い 202",
			r:    authNoBody(http.StatusAccepted),
			want: wantResponse{status: 202, body: ""},
		},
		{
			name: "JSON の本文の null",
			r:    authJSON(http.StatusOK, verifyEmailBody{Result: "EMAIL_VERIFIED"}),
			want: wantResponse{status: 200, contentType: "application/json", body: `{"result":"EMAIL_VERIFIED","passwordResetToken":null}`},
		},
		{
			name: "JSON の本文の値",
			r:    authJSON(http.StatusOK, verifyEmailBody{Result: "PASSWORD_RESET_READY", PasswordResetToken: &token}),
			want: wantResponse{status: 200, contentType: "application/json", body: `{"result":"PASSWORD_RESET_READY","passwordResetToken":"reset-value"}`},
		},
		{
			name: "文字の本文",
			r:    authText("text/plain;charset=UTF-8", "https://accounts.example.com/o?a=1&b=<2>"),
			want: wantResponse{status: 200, contentType: "text/plain;charset=UTF-8", body: "https://accounts.example.com/o?a=1&b=<2>"},
		},
		{
			name: "移る先と Cookie 2つ",
			r:    authRedirect("http://localhost:5173/resume/list", access, refresh),
			want: wantResponse{status: 302, cookies: []string{access, refresh}, location: "http://localhost:5173/resume/list", body: ""},
		},
		{
			name: "移る先だけ",
			r:    authRedirect("http://localhost:5173/login?error=x"),
			want: wantResponse{status: 302, location: "http://localhost:5173/login?error=x", body: ""},
		},
	}
	for _, c := range cases {
		for op, visit := range visitors(c.r) {
			checkResponse(t, c.name+" を "+op+" で書いた", recordResponse(t, visit), c.want)
		}
	}
}

// TestAuthResponses_ErrorBodies は、*auth.Error を、Java 版の AppExceptionHandler と同じ状態の番号と本文と Cookie に
// 変えることを確かめる(要件1.1、1.4)。本文は {message, errors} か、409 のときだけ {message, errors, kind} の順で書き、
// Jackson と同じく < > & を逃がさない。操作の相手の利用者が居ない 401 だけ、accessToken と refreshToken を消す Cookie を
// この順に書く。*auth.Error でない誤りは変えない。
func TestAuthResponses_ErrorBodies(t *testing.T) {
	empty := map[string][]string{}
	cases := []struct {
		name   string
		err    error
		secure bool
		want   wantResponse
	}{
		{
			name: "業務の決まりの 400",
			err:  &auth.Error{Status: 400, Message: auth.MessageLoginFailed, Errors: empty},
			want: wantResponse{status: 400, contentType: "application/json", body: `{"message":"メールアドレスまたはパスワードが正しくありません。","errors":{}}`},
		},
		{
			name: "errors が nil",
			err:  &auth.Error{Status: 400, Message: auth.MessageInvalidAccess},
			want: wantResponse{status: 400, contentType: "application/json", body: `{"message":"不正なアクセスです。","errors":{}}`},
		},
		{
			name: "包んだ誤り",
			err:  fmt.Errorf("包む: %w", &auth.Error{Status: 400, Message: auth.MessageInvalidAccess, Errors: empty}),
			want: wantResponse{status: 400, contentType: "application/json", body: `{"message":"不正なアクセスです。","errors":{}}`},
		},
		{
			name: "409 の PENDING_REGISTRATION",
			err:  &auth.Error{Status: 409, Message: auth.MessageEmailNotVerified, Errors: empty, Kind: auth.KindPendingRegistration},
			want: wantResponse{status: 409, contentType: "application/json", body: `{"message":"メールアドレスの確認が済んでいません。","errors":{},"kind":"PENDING_REGISTRATION"}`},
		},
		{
			name:   "409 の UNVERIFIED_ACCOUNT_EMAIL",
			err:    &auth.Error{Status: 409, Message: auth.MessageEmailNotVerified, Errors: empty, Kind: auth.KindUnverifiedAccountEmail},
			secure: true,
			want:   wantResponse{status: 409, contentType: "application/json", body: `{"message":"メールアドレスの確認が済んでいません。","errors":{},"kind":"UNVERIFIED_ACCOUNT_EMAIL"}`},
		},
		{
			name: "入力の誤りの 400",
			err: &auth.Error{Status: 400, Message: auth.MessageInvalidInput, Errors: map[string][]string{
				"password": {"パスワードは8文字以上で入力してください。", "<&>"}, "email": {"メールアドレスは入力必須です。"},
			}},
			want: wantResponse{status: 400, contentType: "application/json", body: `{"message":"入力エラーがあります。","errors":{"email":["メールアドレスは入力必須です。"],"password":["パスワードは8文字以上で入力してください。","<&>"]}}`},
		},
		{
			name:   "ログインを続けるための値が無効な 401",
			err:    &auth.Error{Status: 401, Message: auth.MessageUnauthenticated, Errors: empty},
			secure: true,
			want:   wantResponse{status: 401, contentType: "application/json", body: `{"message":"認証に失敗しました。","errors":{}}`},
		},
		{
			name: "利用者が居ない 401",
			err:  &auth.Error{Status: 401, Message: auth.MessageUserInfoUnavailable, Errors: empty, ClearSession: true},
			want: wantResponse{status: 401, contentType: "application/json", body: `{"message":"ユーザー情報の取得に失敗しました。","errors":{}}`, cookies: []string{
				"accessToken=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Lax",
				"refreshToken=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Lax",
			}},
		},
		{
			name:   "利用者が居ない 401 で Secure",
			err:    &auth.Error{Status: 401, Message: auth.MessageUserInfoUnavailable, Errors: empty, ClearSession: true},
			secure: true,
			want: wantResponse{status: 401, contentType: "application/json", body: `{"message":"ユーザー情報の取得に失敗しました。","errors":{}}`, cookies: []string{
				"accessToken=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; HttpOnly; SameSite=Lax",
				"refreshToken=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; HttpOnly; SameSite=Lax",
			}},
		},
	}
	for _, c := range cases {
		r, ok := authErrorResponse(c.err, c.secure)
		if !ok {
			t.Errorf("%s: *auth.Error として扱わなかった", c.name)
			continue
		}
		for op, visit := range visitors(r) {
			checkResponse(t, c.name+" を "+op+" で書いた", recordResponse(t, visit), c.want)
		}
	}
	for _, err := range []error{errors.New("ほかの誤り"), nil, ErrNotImplemented} {
		if _, ok := authErrorResponse(err, false); ok {
			t.Errorf("authErrorResponse(%v) を *auth.Error として扱った", err)
		}
	}
}
