package httpapi

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
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

// testNow は、受け口のテストで今の時刻として使う時刻である。
var testNow = time.Date(2026, 11, 11, 3, 4, 5, 0, time.UTC)

// errTestBoom は、*auth.Error でない、データベースなどの誤りの代わりである。
var errTestBoom = errors.New("データベースの誤りの代わり")

// fakeAuth は、認証の処理の代わりである。呼ばれた操作と引数を calls に記録し、決めた結果と err を返す。
type fakeAuth struct {
	calls    []string
	login    auth.LoginResult
	tokens   auth.SessionTokens
	access   string
	verify   auth.VerifyEmailResult
	oidcURL  string
	callback auth.OIDCCallbackResult
	err      error
}

func (f *fakeAuth) record(format string, args ...any) error {
	f.calls = append(f.calls, fmt.Sprintf(format, args...))
	return f.err
}

func (f *fakeAuth) Login(_ context.Context, email, password string) (auth.LoginResult, error) {
	return f.login, f.record("Login(%s,%s)", email, password)
}

func (f *fakeAuth) VerifyTwoFactor(_ context.Context, challenge, code string) (auth.SessionTokens, error) {
	return f.tokens, f.record("VerifyTwoFactor(%s,%s)", challenge, code)
}

func (f *fakeAuth) Refresh(_ context.Context, refreshToken string) (string, error) {
	return f.access, f.record("Refresh(%s)", refreshToken)
}

func (f *fakeAuth) Logout(_ context.Context, refreshToken, accessToken string) error {
	return f.record("Logout(%s,%s)", refreshToken, accessToken)
}

func (f *fakeAuth) Register(_ context.Context, in auth.RegisterInput) error {
	return f.record("Register(%s,%s,%s)", in.Email, in.Username, in.Password)
}

func (f *fakeAuth) VerifyEmail(_ context.Context, token string) (auth.VerifyEmailResult, error) {
	return f.verify, f.record("VerifyEmail(%s)", token)
}

func (f *fakeAuth) ResendEmailVerification(_ context.Context, token string) error {
	return f.record("ResendEmailVerification(%s)", token)
}

func (f *fakeAuth) ResendEmailVerificationForLogin(_ context.Context, email, password string) error {
	return f.record("ResendEmailVerificationForLogin(%s,%s)", email, password)
}

func (f *fakeAuth) RequestPasswordReset(_ context.Context, email string) error {
	return f.record("RequestPasswordReset(%s)", email)
}

func (f *fakeAuth) VerifyPasswordResetToken(_ context.Context, token string) error {
	return f.record("VerifyPasswordResetToken(%s)", token)
}

func (f *fakeAuth) ResetPassword(_ context.Context, token, newPassword string) error {
	return f.record("ResetPassword(%s,%s)", token, newPassword)
}

// newTestAuthHandlers は、今の時刻を testNow に決めた受け口を作る。
func newTestAuthHandlers(svc authService, secure bool) *authHandlers {
	return newAuthHandlers(svc, slog.New(slog.NewTextHandler(io.Discard, nil)), secure, "", func() time.Time { return testNow })
}

// handled は、受け口が返した答えを書いた応答を読む。受け口が誤りを返したら、テストを止める。
func handled(t *testing.T, resp any, err error) wantResponse {
	t.Helper()
	if err != nil {
		t.Fatalf("受け口が誤りを返した: %v", err)
	}
	r, ok := resp.(authResponse)
	if !ok {
		t.Fatalf("受け口の答えの型 = %T, want authResponse", resp)
	}
	return recordResponse(t, r.write)
}

// errorWant は、err を authErrorResponse で変えた応答を読む。
func errorWant(t *testing.T, err error, secure bool) wantResponse {
	t.Helper()
	r, ok := authErrorResponse(err, secure)
	if !ok {
		t.Fatalf("%v は *auth.Error でない", err)
	}
	return recordResponse(t, r.write)
}

// checkCalls は、認証の処理が want の順に呼ばれたことを確かめる。
func checkCalls(t *testing.T, name string, f *fakeAuth, want ...string) {
	t.Helper()
	if len(f.calls) == 0 && len(want) == 0 {
		return
	}
	if !reflect.DeepEqual(f.calls, want) {
		t.Errorf("%s の処理の呼び出し = %q, want %q", name, f.calls, want)
	}
}

func ptr(s string) *string { return &s }

// sessionFake は、どの操作も成功する認証の処理の代わりを作る。ログインは2段階認証が無効な利用者の結果を返す。
func sessionFake() *fakeAuth {
	return &fakeAuth{
		login:  auth.LoginResult{Session: auth.SessionTokens{AccessToken: "login.access", RefreshToken: "login-refresh"}},
		tokens: auth.SessionTokens{AccessToken: "verified.access", RefreshToken: "verified-refresh"},
		access: "refreshed.access",
		verify: auth.VerifyEmailResult{Result: "VERIFIED"},
	}
}

// authOp は、受け口の1つの操作である。call は、ok が真なら検査を通る値で、偽なら検査を通らない値で受け口を呼ぶ。
// invalid は検査を通らない値の誤りで、要求を検査しない操作では nil である。calls は検査を通る値で呼んだときの処理の
// 呼び出しで、want は sessionFake の結果で処理が成功したときの応答である。
type authOp struct {
	name    string
	call    func(h *authHandlers, ok bool) (any, error)
	invalid *auth.Error
	calls   string
	want    func(secure bool) wantResponse
}

func authOps() []authOp {
	ctx := context.Background()
	const email, user, valid8 = "user@example.com", "taro", "Passw0rd1"
	pick := func(ok bool, s string) string {
		if ok {
			return s
		}
		return ""
	}
	return []authOp{
		{
			name: "Login",
			call: func(h *authHandlers, ok bool) (any, error) {
				return h.Login(ctx, gen.LoginRequestObject{Body: &gen.LoginRequest{Email: pick(ok, email), Password: pick(ok, valid8)}})
			},
			invalid: auth.ValidateLogin("", ""),
			calls:   "Login(user@example.com,Passw0rd1)",
			want: func(secure bool) wantResponse {
				return wantResponse{status: 200, cookies: []string{
					auth.SessionCookie("accessToken", "login.access", secure),
					auth.SessionCookie("refreshToken", "login-refresh", secure),
				}}
			},
		},
		{
			name: "VerifyTwoFactorAuth",
			call: func(h *authHandlers, ok bool) (any, error) {
				return h.VerifyTwoFactorAuth(ctx, gen.VerifyTwoFactorAuthRequestObject{
					Params: gen.VerifyTwoFactorAuthParams{TwoFactorChallenge: ptr("challenge-1")},
					Body:   &gen.TwoFactorAuthRequest{Code: pick(ok, "123456")},
				})
			},
			invalid: auth.ValidateTwoFactor(""),
			calls:   "VerifyTwoFactor(challenge-1,123456)",
			want: func(secure bool) wantResponse {
				return wantResponse{status: 200, cookies: []string{
					auth.SessionCookie("accessToken", "verified.access", secure),
					auth.SessionCookie("refreshToken", "verified-refresh", secure),
					auth.DeleteCookie(auth.ChallengeCookieName, auth.ChallengeCookiePath, secure),
				}}
			},
		},
		{
			name: "RefreshToken",
			call: func(h *authHandlers, _ bool) (any, error) {
				return h.RefreshToken(ctx, gen.RefreshTokenRequestObject{Params: gen.RefreshTokenParams{RefreshToken: ptr("refresh-1")}})
			},
			calls: "Refresh(refresh-1)",
			want: func(secure bool) wantResponse {
				return wantResponse{status: 200, cookies: []string{auth.SessionCookie("accessToken", "refreshed.access", secure)}}
			},
		},
		{
			name: "Logout",
			call: func(h *authHandlers, _ bool) (any, error) {
				return h.Logout(ctx, gen.LogoutRequestObject{
					Params: gen.LogoutParams{RefreshToken: ptr("refresh-1"), AccessToken: ptr("access-1")},
				})
			},
			calls: "Logout(refresh-1,access-1)",
			want: func(secure bool) wantResponse {
				return wantResponse{status: 204, cookies: []string{
					auth.DeleteCookie("accessToken", "/", secure),
					auth.DeleteCookie("refreshToken", "/", secure),
				}}
			},
		},
		{
			name: "RegisterUser",
			call: func(h *authHandlers, ok bool) (any, error) {
				return h.RegisterUser(ctx, gen.RegisterUserRequestObject{Body: &gen.UserRegistrationRequest{
					Email: pick(ok, email), Username: pick(ok, user), Password: pick(ok, valid8), ConfirmPassword: pick(ok, valid8),
				}})
			},
			invalid: auth.ValidateRegister("", "", "", ""),
			calls:   "Register(user@example.com,taro,Passw0rd1)",
			want:    func(bool) wantResponse { return wantResponse{status: 202} },
		},
		{
			name: "VerifyEmail",
			call: func(h *authHandlers, ok bool) (any, error) {
				return h.VerifyEmail(ctx, gen.VerifyEmailRequestObject{Body: &gen.EmailVerificationTokenRequest{Token: pick(ok, "verify-1")}})
			},
			invalid: auth.ValidateEmailVerificationToken(""),
			calls:   "VerifyEmail(verify-1)",
			want: func(bool) wantResponse {
				return wantResponse{status: 200, contentType: "application/json", body: `{"result":"VERIFIED","passwordResetToken":null}`}
			},
		},
		{
			name: "ResendEmailVerification",
			call: func(h *authHandlers, ok bool) (any, error) {
				return h.ResendEmailVerification(ctx, gen.ResendEmailVerificationRequestObject{
					Body: &gen.EmailVerificationTokenRequest{Token: pick(ok, "verify-1")},
				})
			},
			invalid: auth.ValidateEmailVerificationToken(""),
			calls:   "ResendEmailVerification(verify-1)",
			want:    func(bool) wantResponse { return wantResponse{status: 204} },
		},
		{
			name: "ResendEmailVerificationForLogin",
			call: func(h *authHandlers, ok bool) (any, error) {
				return h.ResendEmailVerificationForLogin(ctx, gen.ResendEmailVerificationForLoginRequestObject{
					Body: &gen.ResendEmailVerificationForLoginRequest{Email: pick(ok, email), Password: pick(ok, valid8)},
				})
			},
			invalid: auth.ValidateResendEmailVerificationForLogin("", ""),
			calls:   "ResendEmailVerificationForLogin(user@example.com,Passw0rd1)",
			want:    func(bool) wantResponse { return wantResponse{status: 204} },
		},
		{
			name: "RequestPasswordReset",
			call: func(h *authHandlers, ok bool) (any, error) {
				return h.RequestPasswordReset(ctx, gen.RequestPasswordResetRequestObject{
					Body: &gen.RequestPasswordResetRequest{Email: pick(ok, email)},
				})
			},
			invalid: auth.ValidatePasswordResetRequest(""),
			calls:   "RequestPasswordReset(user@example.com)",
			want:    func(bool) wantResponse { return wantResponse{status: 204} },
		},
		{
			name: "VerifyPasswordResetToken",
			call: func(h *authHandlers, _ bool) (any, error) {
				return h.VerifyPasswordResetToken(ctx, gen.VerifyPasswordResetTokenRequestObject{
					Body: &gen.RequestPasswordResetVerifyRequest{Token: ptr("reset-1")},
				})
			},
			calls: "VerifyPasswordResetToken(reset-1)",
			want:  func(bool) wantResponse { return wantResponse{status: 204} },
		},
		{
			name: "ResetPassword",
			call: func(h *authHandlers, ok bool) (any, error) {
				return h.ResetPassword(ctx, gen.ResetPasswordRequestObject{Body: &gen.ResetPasswordRequest{
					Token: ptr("reset-1"), Password: pick(ok, valid8), ConfirmPassword: pick(ok, valid8),
				}})
			},
			invalid: auth.ValidateResetPassword("", ""),
			calls:   "ResetPassword(reset-1,Passw0rd1)",
			want:    func(bool) wantResponse { return wantResponse{status: 204} },
		},
	}
}

// TestAuthHandlers_Operations は、11の操作の受け口が、Java 版の受け口と同じく、要求の値を処理に渡し、成功したら
// 操作ごとの状態の番号と Cookie と本文で答えることを確かめる(要件1.1、1.2)。検査を通らない要求では処理を呼ばずに
// 入力の誤りで答え、処理の *auth.Error は Error の部品の節の形で答え、ほかの誤りはそのまま返す。
func TestAuthHandlers_Operations(t *testing.T) {
	ops := authOps()
	if len(ops) != 11 {
		t.Fatalf("操作の数 = %d, want 11", len(ops))
	}
	denied := &auth.Error{Status: 401, Message: auth.MessageUserInfoUnavailable, Errors: map[string][]string{}, ClearSession: true}
	for _, op := range ops {
		for _, secure := range []bool{false, true} {
			name := fmt.Sprintf("%s(secure=%v)", op.name, secure)
			f := sessionFake()
			resp, err := op.call(newTestAuthHandlers(f, secure), true)
			checkResponse(t, name+" の成功", handled(t, resp, err), op.want(secure))
			checkCalls(t, name+" の成功", f, op.calls)

			if op.invalid != nil {
				f = sessionFake()
				resp, err = op.call(newTestAuthHandlers(f, secure), false)
				checkResponse(t, name+" の検査の誤り", handled(t, resp, err), errorWant(t, op.invalid, secure))
				checkCalls(t, name+" の検査の誤り", f)
			}

			f = sessionFake()
			f.err = denied
			resp, err = op.call(newTestAuthHandlers(f, secure), true)
			checkResponse(t, name+" の処理の *auth.Error", handled(t, resp, err), errorWant(t, denied, secure))
			checkCalls(t, name+" の処理の *auth.Error", f, op.calls)

			f = sessionFake()
			f.err = fmt.Errorf("包む: %w", errTestBoom)
			if _, err = op.call(newTestAuthHandlers(f, secure), true); !errors.Is(err, errTestBoom) {
				t.Errorf("%s のほかの誤り = %v, want %v を包んだ誤り", name, err, errTestBoom)
			}
		}
	}
}

// TestAuthHandlers_MissingValues は、Cookie か本文の任意の項目が無い要求で、受け口が空の値を処理に渡すことを確かめる。
// 処理は、空の値を、Java 版の Cookie が無いときや null と同じに扱う。
func TestAuthHandlers_MissingValues(t *testing.T) {
	ctx := context.Background()
	f := sessionFake()
	h := newTestAuthHandlers(f, false)
	_, _ = h.VerifyTwoFactorAuth(ctx, gen.VerifyTwoFactorAuthRequestObject{Body: &gen.TwoFactorAuthRequest{Code: "123456"}})
	_, _ = h.RefreshToken(ctx, gen.RefreshTokenRequestObject{})
	_, _ = h.Logout(ctx, gen.LogoutRequestObject{})
	_, _ = h.Logout(ctx, gen.LogoutRequestObject{Params: gen.LogoutParams{AccessToken: ptr("access-1")}})
	_, _ = h.VerifyPasswordResetToken(ctx, gen.VerifyPasswordResetTokenRequestObject{Body: &gen.RequestPasswordResetVerifyRequest{}})
	_, _ = h.ResetPassword(ctx, gen.ResetPasswordRequestObject{
		Body: &gen.ResetPasswordRequest{Password: "Passw0rd1", ConfirmPassword: "Passw0rd1"},
	})
	checkCalls(t, "値の無い要求", f,
		"VerifyTwoFactor(,123456)", "Refresh()", "Logout(,)", "Logout(,access-1)", "VerifyPasswordResetToken()", "ResetPassword(,Passw0rd1)")
}

// TestAuthHandlers_LoginNoBody は、ログインの受け口が、Java 版の LoginController と同じく、2段階認証が無効なら
// 200 と Cookie accessToken と refreshToken を、有効なら 202 と Cookie twoFactorChallenge を書き、どちらも本文を
// 書かないことを確かめる(要件1.1、1.2)。twoFactorChallenge の Expires は、受けた時刻の600秒あとである。
func TestAuthHandlers_LoginNoBody(t *testing.T) {
	ctx := context.Background()
	body := &gen.LoginRequest{Email: "user@example.com", Password: "Passw0rd1"}
	for _, secure := range []bool{false, true} {
		f := &fakeAuth{login: auth.LoginResult{Session: auth.SessionTokens{AccessToken: "a.b.c", RefreshToken: "r-1"}}}
		resp, err := newTestAuthHandlers(f, secure).Login(ctx, gen.LoginRequestObject{Body: body})
		checkResponse(t, fmt.Sprintf("2段階認証が無効(secure=%v)", secure), handled(t, resp, err), wantResponse{status: 200, cookies: []string{
			auth.SessionCookie("accessToken", "a.b.c", secure),
			auth.SessionCookie("refreshToken", "r-1", secure),
		}})

		f = &fakeAuth{login: auth.LoginResult{TwoFactorChallenge: "challenge-1"}}
		resp, err = newTestAuthHandlers(f, secure).Login(ctx, gen.LoginRequestObject{Body: body})
		want := wantResponse{status: 202, cookies: []string{auth.ChallengeCookie("challenge-1", secure, testNow)}}
		checkResponse(t, fmt.Sprintf("2段階認証が有効(secure=%v)", secure), handled(t, resp, err), want)
		if !strings.Contains(want.cookies[0], "Expires=Wed, 11 Nov 2026 03:14:05 GMT") {
			t.Errorf("twoFactorChallenge の Cookie = %q, want 受けた時刻の600秒あとの Expires", want.cookies[0])
		}
	}
}

// TestAuthHandlers_VerifyTwoFactorCookieOrder は、2段階認証の受け口が、Java 版の TwoFactorAuthController と同じく、
// Cookie twoFactorChallenge の値を処理に渡し、200 と、accessToken、refreshToken、twoFactorChallenge を消す Cookie を
// この順に書くことを確かめる(要件1.1、1.2)。
func TestAuthHandlers_VerifyTwoFactorCookieOrder(t *testing.T) {
	for _, secure := range []bool{false, true} {
		f := &fakeAuth{tokens: auth.SessionTokens{AccessToken: "x.y.z", RefreshToken: "r-2"}}
		resp, err := newTestAuthHandlers(f, secure).VerifyTwoFactorAuth(context.Background(), gen.VerifyTwoFactorAuthRequestObject{
			Params: gen.VerifyTwoFactorAuthParams{TwoFactorChallenge: ptr("challenge-2")},
			Body:   &gen.TwoFactorAuthRequest{Code: "654321"},
		})
		name := fmt.Sprintf("2段階認証(secure=%v)", secure)
		checkResponse(t, name, handled(t, resp, err), wantResponse{status: 200, cookies: []string{
			auth.SessionCookie("accessToken", "x.y.z", secure),
			auth.SessionCookie("refreshToken", "r-2", secure),
			auth.DeleteCookie("twoFactorChallenge", "/api/auth/2fa", secure),
		}})
		checkCalls(t, name, f, "VerifyTwoFactor(challenge-2,654321)")
	}
}

// TestAuthHandlers_VerifyTwoFactorNoChallenge400 は、Cookie twoFactorChallenge が無いか空の要求に、Java 版と同じく、
// 入力の検査のあとに 400 と「認証セッションが無効または期限切れです。…」で答えることを確かめる(要件1.1、1.2)。
// 本物の認証の処理を使う。この断り方は、Redis とデータベースを読む前に決まる。
func TestAuthHandlers_VerifyTwoFactorNoChallenge400(t *testing.T) {
	h := newTestAuthHandlers(auth.New(auth.Deps{}), false)
	ctx := context.Background()
	session := &auth.Error{Status: 400, Message: auth.MessageInvalidTwoFactorSession, Errors: map[string][]string{}}
	cases := []struct {
		name      string
		challenge *string
		code      string
		want      error
	}{
		{
			name: "Cookie が無い",
			code: "123456",
			want: session,
		},
		{
			name:      "Cookie が空",
			challenge: ptr(""),
			code:      "123456",
			want:      session,
		},
		{
			name: "Cookie が無く確認のコードも無い",
			code: "",
			want: auth.ValidateTwoFactor(""),
		},
	}
	for _, c := range cases {
		resp, err := h.VerifyTwoFactorAuth(ctx, gen.VerifyTwoFactorAuthRequestObject{
			Params: gen.VerifyTwoFactorAuthParams{TwoFactorChallenge: c.challenge},
			Body:   &gen.TwoFactorAuthRequest{Code: c.code},
		})
		checkResponse(t, c.name, handled(t, resp, err), errorWant(t, c.want, false))
	}
}

// TestAuthHandlers_VerifyEmailNullToken は、メールアドレスの確認の受け口が、Java 版の VerifyEmailResponse と同じく、
// 再設定の値が無い結果では passwordResetToken を null と書き、ある結果では値を書くことを確かめる(要件1.1、1.2)。
func TestAuthHandlers_VerifyEmailNullToken(t *testing.T) {
	cases := []struct {
		result auth.VerifyEmailResult
		body   string
	}{
		{
			result: auth.VerifyEmailResult{Result: "VERIFIED"},
			body:   `{"result":"VERIFIED","passwordResetToken":null}`,
		},
		{
			result: auth.VerifyEmailResult{Result: "EXPIRED"},
			body:   `{"result":"EXPIRED","passwordResetToken":null}`,
		},
		{
			result: auth.VerifyEmailResult{Result: "PASSWORD_RESET_READY", PasswordResetToken: "reset-9"},
			body:   `{"result":"PASSWORD_RESET_READY","passwordResetToken":"reset-9"}`,
		},
	}
	for _, c := range cases {
		f := &fakeAuth{verify: c.result}
		resp, err := newTestAuthHandlers(f, false).VerifyEmail(context.Background(), gen.VerifyEmailRequestObject{
			Body: &gen.EmailVerificationTokenRequest{Token: "verify-9"},
		})
		checkResponse(t, c.result.Result, handled(t, resp, err), wantResponse{status: 200, contentType: "application/json", body: c.body})
	}
}

func (f *fakeAuth) StartOIDC(_ context.Context, provider, redirectURI string) (string, error) {
	if err := f.record("StartOIDC(%s,%s)", provider, redirectURI); err != nil {
		return "", err
	}
	return f.oidcURL, nil
}

func (f *fakeAuth) HandleOIDCCallback(_ context.Context, code, state, errParam *string, redirectURI string) auth.OIDCCallbackResult {
	_ = f.record("HandleOIDCCallback(%s,%s,%s,%s)", show(code), show(state), show(errParam), redirectURI)
	return f.callback
}

// show は、無い値を <nil> と書く。
func show(p *string) string {
	if p == nil {
		return "<nil>"
	}
	return *p
}

// oidcTestServer は、Google と GitHub の2つの操作だけを受け口に渡す、生成したコードの受け口の束である。
type oidcTestServer struct {
	Unimplemented
	h *authHandlers
}

func (s oidcTestServer) StartOidcAuthorization(
	ctx context.Context, req gen.StartOidcAuthorizationRequestObject,
) (gen.StartOidcAuthorizationResponseObject, error) {
	return s.h.StartOidcAuthorization(ctx, req)
}

func (s oidcTestServer) HandleOidcCallback(
	ctx context.Context, req gen.HandleOidcCallbackRequestObject,
) (gen.HandleOidcCallbackResponseObject, error) {
	return s.h.HandleOidcCallback(ctx, req)
}

// oidcServer は、受け口 h を、要求の Host と Accept を context に入れる中間処理を通して呼ぶ形にする。
// 受け口が誤りを返したときは 500 と errTestBoom の文で答える。
func oidcServer(h *authHandlers) gen.ServerInterface {
	return gen.NewStrictHandlerWithOptions(oidcTestServer{h: h}, []gen.StrictMiddlewareFunc{authRequestMiddleware},
		gen.StrictHTTPServerOptions{
			ResponseErrorHandlerFunc: func(w http.ResponseWriter, _ *http.Request, err error) {
				http.Error(w, err.Error(), http.StatusInternalServerError)
			},
		})
}

// startOIDC は、Host と Accept の行を付けたログインの開始の要求を送る。accept が nil なら Accept を付けない。
func startOIDC(h *authHandlers, provider, host string, accept []string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(http.MethodGet, "/api/auth/oidc/authorize?provider="+provider, http.NoBody)
	r.Host = host
	for _, a := range accept {
		r.Header.Add("Accept", a)
	}
	w := httptest.NewRecorder()
	oidcServer(h).StartOidcAuthorization(w, r, gen.StartOidcAuthorizationParams{Provider: provider})
	return w
}

// TestAuthOIDCHandlers_ContentTypeByAccept は、ログインの開始の応答の Content-Type が、Java 版の Spring と同じく
// Accept で決まることを確かめる(要件1.3)。期待する値は、Java 版に同じ Accept を送って返った文字列である。
// Java 版の Spring は、Accept の型を q の値と具体さの順に並べ、文字列を書ける型のうち最初の具体的な型を選ぶ。
func TestAuthOIDCHandlers_ContentTypeByAccept(t *testing.T) {
	const plain = "text/plain;charset=UTF-8"
	many := func(n int) []string { return []string{strings.TrimSuffix(strings.Repeat("*/*,", n), ",")} }
	cases := []struct {
		name   string
		accept []string
		want   string
	}{
		{name: "Accept が無い", accept: nil, want: plain},
		{name: "*/*", accept: []string{"*/*"}, want: plain},
		{name: "axios の既定", accept: []string{"application/json, text/plain, */*"}, want: "application/json"},
		{name: "text/plain", accept: []string{"text/plain"}, want: plain},
		{name: "application/json", accept: []string{"application/json"}, want: "application/json"},
		{name: "*/* のあとの application/json", accept: []string{"*/*, application/json"}, want: "application/json"},
		{name: "空の Accept", accept: []string{""}, want: plain},
		{name: "* だけ", accept: []string{"*"}, want: plain},
		{name: "大文字の型", accept: []string{"TEXT/Plain"}, want: plain},
		{name: "q の値の大きい text/plain", accept: []string{"application/json;q=0.5, text/plain"}, want: plain},
		{name: "q=0 も選ぶ", accept: []string{"text/plain;q=0, application/json;q=0.1"}, want: "application/json"},
		{name: "*/*;q=0", accept: []string{"*/*;q=0"}, want: plain},
		{name: "text/* より application/json", accept: []string{"text/*, application/json"}, want: "application/json"},
		{name: "application/*", accept: []string{"application/*"}, want: "application/json"},
		{name: "application/*+json", accept: []string{"application/*+json;q=0.5, text/plain"}, want: plain},
		{name: "同じ q の */* と application/json", accept: []string{"*/*;q=0.5, application/json;q=0.5"}, want: "application/json"},
		{name: "同じ q の text/plain", accept: []string{"*/*;q=0.9, text/plain;q=0.9"}, want: plain},
		{name: "先に書いた text/plain", accept: []string{"text/plain, application/json"}, want: plain},
		{name: "先に書いた application/json", accept: []string{"application/json, text/plain"}, want: "application/json"},
		{
			name:   "ブラウザの既定",
			accept: []string{"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
			want:   "text/html;charset=UTF-8",
		},
		{name: "image/png", accept: []string{"image/png"}, want: "image/png;charset=UTF-8"},
		{name: "application/xml", accept: []string{"application/xml"}, want: "application/xml;charset=UTF-8"},
		{name: "+json の型", accept: []string{"application/problem+json"}, want: "application/problem+json"},
		{name: "json で終わらない型", accept: []string{"a+b/c+json"}, want: "a+b/c+json;charset=UTF-8"},
		{name: "JSON の引数はそのまま", accept: []string{"application/json;Foo=Bar"}, want: "application/json;Foo=Bar"},
		{
			name:   "JSON の charset は最後",
			accept: []string{"application/vnd.a+json;charset=utf-8;x=y"},
			want:   "application/vnd.a+json;x=y;charset=utf-8",
		},
		{name: "JSON の charset", accept: []string{"application/json;charset=UTF-8"}, want: "application/json;charset=UTF-8"},
		{name: "charset の名前の大文字", accept: []string{"text/plain;Charset=utf-8"}, want: "text/plain;charset=utf-8"},
		{name: "引用符の charset", accept: []string{`text/plain;charset="utf-8"`}, want: "text/plain;charset=utf-8"},
		{name: "空白の入った charset", accept: []string{"text/plain ; charset = utf-8"}, want: "text/plain;charset=utf-8"},
		{
			name:   "charset のあとの引数",
			accept: []string{"text/plain;charset=utf-8;format=flowed"},
			want:   "text/plain;format=flowed;charset=utf-8",
		},
		{name: "引数の名前は小文字", accept: []string{"text/plain;Format=flowed"}, want: "text/plain;format=flowed;charset=UTF-8"},
		{
			name:   "q を除いた引数",
			accept: []string{"text/plain; format=flowed; q=0.9"},
			want:   "text/plain;format=flowed;charset=UTF-8",
		},
		{name: "q のあとの引数", accept: []string{"text/plain;a=b;q=0.5;c=d"}, want: "text/plain;a=b;c=d;charset=UTF-8"},
		{name: "大文字の Q は残る", accept: []string{"text/plain;Q=0.5"}, want: "text/plain;q=0.5;charset=UTF-8"},
		{name: "引用符の中の区切り", accept: []string{`text/plain;a="b,c"`}, want: `text/plain;a="b,c";charset=UTF-8`},
		{name: "引用符の中の空白", accept: []string{`text/plain;a="b c"`}, want: `text/plain;a="b c";charset=UTF-8`},
		{name: "= の無い引数", accept: []string{"text/plain;foo"}, want: plain},
		{name: "引数の多い型", accept: []string{"text/plain;a=1, text/plain"}, want: "text/plain;a=1;charset=UTF-8"},
		{name: "後の q", accept: []string{"text/plain;q=0.5;q=0.7"}, want: plain},
		{name: "引用符の q", accept: []string{`text/plain;q="0.5"`}, want: plain},
		{name: "小数点で始まる q", accept: []string{"text/plain;q=.5"}, want: plain},
		{name: "d で終わる q", accept: []string{"text/plain;q=0.5d"}, want: plain},
		{name: "指数の q", accept: []string{"text/plain;q=1e0"}, want: plain},
		{name: "charset の別名", accept: []string{"text/plain;charset=Shift_JIS"}, want: "text/plain;charset=Shift_JIS"},
		{name: "2行の Accept", accept: []string{"text/plain;q=0.1", "application/json"}, want: "application/json"},
		{name: "空の行と Accept", accept: []string{"", "application/json"}, want: "application/json"},
		{name: "50の型", accept: many(50), want: plain},
		{name: "q の高い具体的な型", accept: []string{"text/html;q=0.8, */*;q=0.5"}, want: "text/html;charset=UTF-8"},
		{
			name:   "名前の大文字と小文字の違う charset",
			accept: []string{"text/plain;Charset=utf-8;charset=EUC-JP"},
			want:   "text/plain;charset=EUC-JP",
		},
		{name: "同じ名前の引数", accept: []string{"text/plain;a=1;b=2;a=3"}, want: "text/plain;a=3;b=2;charset=UTF-8"},
		{name: `\ のあとの引用符`, accept: []string{`text/plain;a="b\",c"`}, want: `text/plain;a="b\",c";charset=UTF-8`},
		{name: "引用符の中の ;", accept: []string{`text/plain;a="b;c"`}, want: `text/plain;a="b;c";charset=UTF-8`},
		{name: "最後の空の型", accept: []string{"text/plain, "}, want: plain},
		{name: "application/*+json だけ", accept: []string{"application/*+json"}, want: "application/json"},
		{name: "text/*", accept: []string{"text/*"}, want: plain},
		{name: "違う型の引数の数", accept: []string{"text/plain, application/json;a=1"}, want: plain},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := &fakeAuth{oidcURL: "https://accounts.example/auth?x=1&y=2"}
			w := startOIDC(newTestAuthHandlers(f, false), "google", "localhost:8080", c.accept)
			if w.Code != http.StatusOK || w.Header().Get("Content-Type") != c.want || w.Body.String() != f.oidcURL {
				t.Errorf("答え = %d %q %q、期待 = 200 %q %q", w.Code, w.Header().Get("Content-Type"), w.Body.String(), c.want, f.oidcURL)
			}
		})
	}

	// Java 版が 406 で答える Accept。Java 版で 401 になる image/* は、406 の答えを Java 版の誤りの画面が 401 に
	// 書き換えたものである(変えた動きの一覧に書く)
	rejected := []struct {
		name   string
		accept []string
	}{
		{name: "型でない", accept: []string{"foo"}},
		{name: "下位の型だけ", accept: []string{"text"}},
		{name: "型の無い", accept: []string{"/plain"}},
		{name: "下位の型の無い", accept: []string{"text/"}},
		{name: "* の型", accept: []string{"*/json"}},
		{name: "空白の入った型", accept: []string{"text/pl ain"}},
		{name: "日本語の型", accept: []string{"text/文字"}},
		{name: "1 を超える q", accept: []string{"text/plain;q=2"}},
		{name: "大文字の Q の誤り", accept: []string{"text/plain;Q=abc"}},
		{name: "数でない q", accept: []string{"text/plain;q=abc"}},
		{name: "負の q", accept: []string{"text/plain;q=-0.1"}},
		{name: "空の引数の値", accept: []string{"text/plain;a="}},
		{name: "空の引数の名前", accept: []string{"text/plain;=x"}},
		{name: "空白の入った引数の値", accept: []string{"text/plain;a=b c"}},
		{name: "記号で始まる charset", accept: []string{"text/plain;charset=-utf8"}},
		{name: "空の charset", accept: []string{`text/plain;charset=""`}},
		{name: "記号の入った charset", accept: []string{"text/plain;Charset=utf/8"}},
		{name: "51の型", accept: many(51)},
		{name: "具体的な型が無い", accept: []string{"image/*"}},
		{name: "2行目の誤り", accept: []string{"text/plain", "foo"}},
	}
	for _, c := range rejected {
		t.Run("406 "+c.name, func(t *testing.T) {
			f := &fakeAuth{oidcURL: "https://accounts.example/auth"}
			w := startOIDC(newTestAuthHandlers(f, false), "google", "localhost:8080", c.accept)
			if w.Code != http.StatusNotAcceptable || w.Header().Get("Content-Type") != "" || w.Body.Len() != 0 {
				t.Errorf("答え = %d %q %q、期待 = 406 で本文と Content-Type が無い", w.Code, w.Header().Get("Content-Type"), w.Body.String())
			}
			checkCalls(t, c.name, f, "StartOIDC(google,http://localhost:8080/api/auth/oidc/callback)")
		})
	}
}

// TestAuthOIDCHandlers_StartErrorBeforeAccept は、ログインの開始の処理の誤りが、Java 版と同じく Accept を見る前に
// 決まることを確かめる(要件1.3)。知らない provider は、読めない Accept でも 400 と誤りの本文で答える。
func TestAuthOIDCHandlers_StartErrorBeforeAccept(t *testing.T) {
	w := startOIDC(newTestAuthHandlers(auth.New(auth.Deps{}), false), "nope", "localhost:8080", []string{"foo"})
	if w.Code != http.StatusBadRequest || w.Body.String() != `{"message":"入力エラーがあります。","errors":{}}` {
		t.Errorf("答え = %d %q、期待 = 400 と入力の誤りの本文", w.Code, w.Body.String())
	}

	f := &fakeAuth{err: errTestBoom}
	w = startOIDC(newTestAuthHandlers(f, false), "google", "localhost:8080", []string{"foo"})
	if w.Code != http.StatusInternalServerError || !strings.Contains(w.Body.String(), errTestBoom.Error()) {
		t.Errorf("答え = %d %q、期待 = 誤りを返して 500", w.Code, w.Body.String())
	}
}

// TestAuthOIDCHandlers_RedirectURIPort80 は、戻り先の URL を、Java 版の DevBaseUrlResolver と同じく要求の Host から、
// 本番では設定 App.APIBaseURL から作ることを確かめる(要件1.3)。期待する値は、Java 版に同じ Host を送って
// 返った redirect_uri である。ポートが 80 ならポートを書かず、ポートは数として読み直す。
func TestAuthOIDCHandlers_RedirectURIPort80(t *testing.T) {
	const path = "/api/auth/oidc/callback"
	cases := []struct {
		name, base, host, want string
	}{
		{name: "ポート80", host: "localhost:80", want: "http://localhost" + path},
		{name: "ポートが無い", host: "localhost", want: "http://localhost" + path},
		{name: "検査の Host", host: "compat.test", want: "http://compat.test" + path},
		{name: "ポート8080", host: "localhost:8080", want: "http://localhost:8080" + path},
		{name: "大文字の名前", host: "LocalHost:8080", want: "http://LocalHost:8080" + path},
		{name: "ポート443", host: "example.com:443", want: "http://example.com:443" + path},
		{name: "0 で始まるポート", host: "localhost:08080", want: "http://localhost:8080" + path},
		{name: "0 で始まるポート80", host: "localhost:0080", want: "http://localhost" + path},
		{name: "空のポート", host: "localhost:", want: "http://localhost:0" + path},
		{name: "IPv6", host: "[::1]:8080", want: "http://[::1]:8080" + path},
		{name: "IPv6 のポート80", host: "[::1]:80", want: "http://[::1]" + path},
		{name: "IPv6 のポートが無い", host: "[::1]", want: "http://[::1]" + path},
		{name: "数でないポート", host: "localhost:8o", want: "http://localhost:8o" + path},
		{name: "本番", base: "https://app.keirekipro.click", host: "localhost:80", want: "https://app.keirekipro.click" + path},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := &fakeAuth{oidcURL: "https://accounts.example/auth"}
			h := newTestAuthHandlers(f, false)
			h.apiBaseURL = c.base
			startOIDC(h, "github", c.host, nil)
			w := callbackOIDC(h, c.host, gen.HandleOidcCallbackParams{})
			if w.Code != http.StatusFound {
				t.Fatalf("戻り先の答え = %d、期待 = 302", w.Code)
			}
			checkCalls(t, c.name, f, "StartOIDC(github,"+c.want+")", "HandleOIDCCallback(<nil>,<nil>,<nil>,"+c.want+")")
		})
	}
}

// TestAuthOIDCHandlers_MiddlewareOnlyOIDC は、要求の Host と Accept を context に入れる中間処理が、Google と GitHub の
// 2つの操作のときだけ値を入れることを確かめる。
func TestAuthOIDCHandlers_MiddlewareOnlyOIDC(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
	r.Host = "compat.test"
	r.Header.Add("Accept", "text/plain")
	r.Header.Add("Accept", "application/json")
	for op, want := range map[string]authRequestInfo{
		"StartOidcAuthorization": {host: "compat.test", accept: []string{"text/plain", "application/json"}},
		"HandleOidcCallback":     {host: "compat.test", accept: []string{"text/plain", "application/json"}},
		"Login":                  {},
	} {
		var got authRequestInfo
		next := func(ctx context.Context, _ http.ResponseWriter, _ *http.Request, _ any) (any, error) {
			got = requestInfo(ctx)
			return nil, nil
		}
		if _, err := authRequestMiddleware(next, op)(context.Background(), httptest.NewRecorder(), r, nil); err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("%s の context の値 = %+v、期待 = %+v", op, got, want)
		}
	}
}

// callbackOIDC は、Host を付けた戻り先の要求を送る。
func callbackOIDC(h *authHandlers, host string, p gen.HandleOidcCallbackParams) *httptest.ResponseRecorder {
	r := httptest.NewRequest(http.MethodGet, "/api/auth/oidc/callback", http.NoBody)
	r.Host = host
	w := httptest.NewRecorder()
	oidcServer(h).HandleOidcCallback(w, r, p)
	return w
}

// TestAuthOIDCHandlers_CallbackFailure302NoBody は、戻り先の要求に、Java 版の OidcCallbackController と同じく、
// 成功なら 302 と Cookie accessToken と refreshToken で、失敗なら 302 だけで、どちらも本文を書かずに答えることを
// 確かめる(要件1.3)。失敗の元の誤りはログに書く。
func TestAuthOIDCHandlers_CallbackFailure302NoBody(t *testing.T) {
	const front = "http://localhost:5174"
	session := auth.SessionTokens{AccessToken: "a.b.c", RefreshToken: "d.e.f"}
	cases := []struct {
		name     string
		secure   bool
		result   auth.OIDCCallbackResult
		cookies  []string
		logWants []string
	}{
		{
			name:   "成功",
			result: auth.OIDCCallbackResult{Location: front + "/resume/list", Session: session},
			cookies: []string{
				auth.SessionCookie("accessToken", "a.b.c", false), auth.SessionCookie("refreshToken", "d.e.f", false),
			},
		},
		{
			name:   "Secure の成功",
			secure: true,
			result: auth.OIDCCallbackResult{Location: front + "/resume/list", Session: session},
			cookies: []string{
				auth.SessionCookie("accessToken", "a.b.c", true), auth.SessionCookie("refreshToken", "d.e.f", true),
			},
		},
		{
			name:     "失敗",
			result:   auth.OIDCCallbackResult{Location: front + "/login?error=x", Cause: errTestBoom},
			logWants: []string{`"msg":"oidc_callback_error"`, `"level":"ERROR"`, errTestBoom.Error()},
		},
		{
			name:   "元の誤りの無い失敗",
			result: auth.OIDCCallbackResult{Location: front + "/login?error=unverified_email"},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var logs strings.Builder
			f := &fakeAuth{callback: c.result}
			h := newTestAuthHandlers(f, c.secure)
			h.logger = slog.New(slog.NewJSONHandler(&logs, nil))
			code, state, denied := "c1", "s1", "access_denied"
			w := callbackOIDC(h, "localhost:8080", gen.HandleOidcCallbackParams{Code: &code, State: &state, Error: &denied})
			checkCalls(t, c.name, f, "HandleOIDCCallback(c1,s1,access_denied,http://localhost:8080/api/auth/oidc/callback)")
			if w.Code != http.StatusFound || w.Header().Get("Location") != c.result.Location {
				t.Errorf("答え = %d %q、期待 = 302 %q", w.Code, w.Header().Get("Location"), c.result.Location)
			}
			if got := w.Header().Values("Set-Cookie"); !reflect.DeepEqual(got, c.cookies) {
				t.Errorf("Set-Cookie = %q、期待 = %q", got, c.cookies)
			}
			if w.Body.Len() != 0 || w.Header().Get("Content-Type") != "" {
				t.Errorf("本文 = %q、Content-Type = %q、期待 = どちらも無い", w.Body.String(), w.Header().Get("Content-Type"))
			}
			for _, s := range c.logWants {
				if !strings.Contains(logs.String(), s) {
					t.Errorf("ログ = %q、期待 = %q を含む", logs.String(), s)
				}
			}
			if c.logWants == nil && logs.Len() != 0 {
				t.Errorf("ログ = %q、期待 = 書かない", logs.String())
			}
		})
	}
}

// TestAuthOIDCHandlers_CompatibleWith は、型が重なるかの判定が、Spring の MimeType.isCompatibleWith の説明の例と
// 同じになることを確かめる。+ のあとが同じ型どうしは、Accept の型と文字列を書ける型の組み合わせでは答えに出ないため、
// ここで直接確かめる。
func TestAuthOIDCHandlers_CompatibleWith(t *testing.T) {
	mt := func(s string) mediaType {
		m, ok := parseMediaType(s)
		if !ok {
			t.Fatalf("%q を読めない", s)
		}
		return m
	}
	cases := []struct {
		a, b string
		want bool
	}{
		{a: "*/*", b: "text/plain", want: true},
		{a: "text/plain", b: "*/*", want: true},
		{a: "text/*", b: "text/plain", want: true},
		{a: "text/plain", b: "text/*", want: true},
		{a: "text/plain", b: "text/html", want: false},
		{a: "text/plain", b: "application/plain", want: false},
		{a: "application/*+xml", b: "application/soap+xml", want: true},
		{a: "application/soap+xml", b: "application/*+xml", want: true},
		{a: "application/*+json", b: "application/json", want: true},
		{a: "application/json", b: "application/*+json", want: true},
		{a: "application/*+json", b: "application/*+xml", want: false},
		{a: "application/*+json", b: "text/json", want: false},
		{a: "application/xml", b: "application/*+json", want: false},
	}
	for _, c := range cases {
		if got := mt(c.a).compatibleWith(mt(c.b)); got != c.want {
			t.Errorf("%s と %s が重なるか = %v、期待 = %v", c.a, c.b, got, c.want)
		}
	}
}
