package httpapi

import (
	"context"
	"errors"
	"fmt"
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
	calls  []string
	login  auth.LoginResult
	tokens auth.SessionTokens
	access string
	verify auth.VerifyEmailResult
	err    error
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
	return newAuthHandlers(svc, secure, func() time.Time { return testNow })
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
	h := newAuthHandlers(auth.New(auth.Deps{}), false, time.Now)
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
