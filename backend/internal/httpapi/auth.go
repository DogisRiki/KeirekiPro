package httpapi

import (
	"context"
	"net/http"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
)

// authService は、受け口が使う認証の処理である。*auth.Service が満たす。
type authService interface {
	Login(ctx context.Context, email, password string) (auth.LoginResult, error)
	VerifyTwoFactor(ctx context.Context, challenge, code string) (auth.SessionTokens, error)
	Refresh(ctx context.Context, refreshToken string) (string, error)
	Logout(ctx context.Context, refreshToken, accessToken string) error
	Register(ctx context.Context, in auth.RegisterInput) error
	VerifyEmail(ctx context.Context, token string) (auth.VerifyEmailResult, error)
	ResendEmailVerification(ctx context.Context, token string) error
	ResendEmailVerificationForLogin(ctx context.Context, email, password string) error
	RequestPasswordReset(ctx context.Context, email string) error
	VerifyPasswordResetToken(ctx context.Context, token string) error
	ResetPassword(ctx context.Context, token, newPassword string) error
}

var _ authService = (*auth.Service)(nil)

// authHandlers は、認証の操作の受け口である。要求の値を検査して認証の処理に渡し、結果を Java 版の受け口と同じ
// 状態の番号と Cookie と本文で答える。*auth.Error は authErrorResponse の形で答え、ほかの誤りは、生成したコードの
// 誤りの処理に渡して 500 にする。
type authHandlers struct {
	svc authService
	// secure は、Cookie に Secure を付けるかである。
	secure bool
	// now は、今の時刻を返す。Cookie twoFactorChallenge の Expires に使う。
	now func() time.Time
}

// newAuthHandlers は、認証の操作の受け口を作る。
func newAuthHandlers(svc authService, secure bool, now func() time.Time) *authHandlers {
	return &authHandlers{svc: svc, secure: secure, now: now}
}

// fail は、err が *auth.Error を含めばその応答を、含まなければ err をそのまま返す。
func (h *authHandlers) fail(err error) (authResponse, error) {
	if r, ok := authErrorResponse(err, h.secure); ok {
		return r, nil
	}
	return authResponse{}, err
}

// sessionCookies は、Java 版の AuthCookieIssuer と同じく、Cookie accessToken と refreshToken をこの順に並べる。
func (h *authHandlers) sessionCookies(s auth.SessionTokens) []string {
	return []string{
		auth.SessionCookie("accessToken", s.AccessToken, h.secure),
		auth.SessionCookie("refreshToken", s.RefreshToken, h.secure),
	}
}

// value は、無い Cookie と本文の項目を空の値にする。認証の処理は、空の値を Java 版の値が無いときと同じに扱う。
func value(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

// Login は、ログインする。2段階認証が有効な利用者には 202 と Cookie twoFactorChallenge で、無効な利用者には
// 200 と Cookie accessToken と refreshToken で答える。どちらも本文を書かない。
func (h *authHandlers) Login(ctx context.Context, req gen.LoginRequestObject) (gen.LoginResponseObject, error) {
	if e := auth.ValidateLogin(req.Body.Email, req.Body.Password); e != nil {
		return h.fail(e)
	}
	res, err := h.svc.Login(ctx, req.Body.Email, req.Body.Password)
	if err != nil {
		return h.fail(err)
	}
	if res.TwoFactorChallenge != "" {
		return authNoBody(http.StatusAccepted, auth.ChallengeCookie(res.TwoFactorChallenge, h.secure, h.now())), nil
	}
	return authNoBody(http.StatusOK, h.sessionCookies(res.Session)...), nil
}

// VerifyTwoFactorAuth は、2段階認証の確認のコードを確かめる。確認のコードを検査してから、Cookie twoFactorChallenge
// の値を処理に渡す。成功したら 200 と、Cookie accessToken、refreshToken、twoFactorChallenge を消す Cookie で答える。
func (h *authHandlers) VerifyTwoFactorAuth(
	ctx context.Context, req gen.VerifyTwoFactorAuthRequestObject,
) (gen.VerifyTwoFactorAuthResponseObject, error) {
	if e := auth.ValidateTwoFactor(req.Body.Code); e != nil {
		return h.fail(e)
	}
	s, err := h.svc.VerifyTwoFactor(ctx, value(req.Params.TwoFactorChallenge), req.Body.Code)
	if err != nil {
		return h.fail(err)
	}
	cookies := append(h.sessionCookies(s), auth.DeleteCookie(auth.ChallengeCookieName, auth.ChallengeCookiePath, h.secure))
	return authNoBody(http.StatusOK, cookies...), nil
}

// RefreshToken は、Cookie refreshToken で、アクセストークンを作り直す。200 と Cookie accessToken で答える。
func (h *authHandlers) RefreshToken(ctx context.Context, req gen.RefreshTokenRequestObject) (gen.RefreshTokenResponseObject, error) {
	access, err := h.svc.Refresh(ctx, value(req.Params.RefreshToken))
	if err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusOK, auth.SessionCookie("accessToken", access, h.secure)), nil
}

// Logout は、ログアウトする。204 と、Cookie accessToken と refreshToken を消す Cookie で答える。
func (h *authHandlers) Logout(ctx context.Context, req gen.LogoutRequestObject) (gen.LogoutResponseObject, error) {
	if err := h.svc.Logout(ctx, value(req.Params.RefreshToken), value(req.Params.AccessToken)); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent,
		auth.DeleteCookie("accessToken", "/", h.secure), auth.DeleteCookie("refreshToken", "/", h.secure)), nil
}

// RegisterUser は、新規に登録する。202 で答える。
func (h *authHandlers) RegisterUser(ctx context.Context, req gen.RegisterUserRequestObject) (gen.RegisterUserResponseObject, error) {
	b := req.Body
	if e := auth.ValidateRegister(b.Email, b.Username, b.Password, b.ConfirmPassword); e != nil {
		return h.fail(e)
	}
	if err := h.svc.Register(ctx, auth.RegisterInput{Email: b.Email, Username: b.Username, Password: b.Password}); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusAccepted), nil
}

// VerifyEmail は、メールアドレスを確かめる。200 と {result, passwordResetToken} で答える。
func (h *authHandlers) VerifyEmail(ctx context.Context, req gen.VerifyEmailRequestObject) (gen.VerifyEmailResponseObject, error) {
	if e := auth.ValidateEmailVerificationToken(req.Body.Token); e != nil {
		return h.fail(e)
	}
	res, err := h.svc.VerifyEmail(ctx, req.Body.Token)
	if err != nil {
		return h.fail(err)
	}
	body := verifyEmailBody{Result: res.Result}
	if res.PasswordResetToken != "" {
		body.PasswordResetToken = &res.PasswordResetToken
	}
	return authJSON(http.StatusOK, body), nil
}

// ResendEmailVerification は、確認のメールを送り直す。204 で答える。
func (h *authHandlers) ResendEmailVerification(
	ctx context.Context, req gen.ResendEmailVerificationRequestObject,
) (gen.ResendEmailVerificationResponseObject, error) {
	if e := auth.ValidateEmailVerificationToken(req.Body.Token); e != nil {
		return h.fail(e)
	}
	if err := h.svc.ResendEmailVerification(ctx, req.Body.Token); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}

// ResendEmailVerificationForLogin は、ログインの画面から確認のメールを送り直す。204 で答える。
func (h *authHandlers) ResendEmailVerificationForLogin(
	ctx context.Context, req gen.ResendEmailVerificationForLoginRequestObject,
) (gen.ResendEmailVerificationForLoginResponseObject, error) {
	if e := auth.ValidateResendEmailVerificationForLogin(req.Body.Email, req.Body.Password); e != nil {
		return h.fail(e)
	}
	if err := h.svc.ResendEmailVerificationForLogin(ctx, req.Body.Email, req.Body.Password); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}

// RequestPasswordReset は、パスワードの再設定のメールを送る。204 で答える。
func (h *authHandlers) RequestPasswordReset(
	ctx context.Context, req gen.RequestPasswordResetRequestObject,
) (gen.RequestPasswordResetResponseObject, error) {
	if e := auth.ValidatePasswordResetRequest(req.Body.Email); e != nil {
		return h.fail(e)
	}
	if err := h.svc.RequestPasswordReset(ctx, req.Body.Email); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}

// VerifyPasswordResetToken は、パスワードの再設定の値が有効かを確かめる。Java 版と同じく本文を検査しない。204 で答える。
func (h *authHandlers) VerifyPasswordResetToken(
	ctx context.Context, req gen.VerifyPasswordResetTokenRequestObject,
) (gen.VerifyPasswordResetTokenResponseObject, error) {
	if err := h.svc.VerifyPasswordResetToken(ctx, value(req.Body.Token)); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}

// ResetPassword は、パスワードを再設定する。Java 版と同じく、新しいパスワードを検査し、再設定の値は検査しない。
// 204 で答える。
func (h *authHandlers) ResetPassword(ctx context.Context, req gen.ResetPasswordRequestObject) (gen.ResetPasswordResponseObject, error) {
	b := req.Body
	if e := auth.ValidateResetPassword(b.Password, b.ConfirmPassword); e != nil {
		return h.fail(e)
	}
	if err := h.svc.ResetPassword(ctx, value(b.Token), b.Password); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}
