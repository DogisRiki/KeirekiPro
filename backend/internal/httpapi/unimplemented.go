package httpapi

import (
	"context"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
)

// Unimplemented は、仕様書のすべての操作を、ErrNotImplemented を返す仮の実装で満たす。
// HTTP の受け口は、ErrNotImplemented を 501 と {"message":"未実装です。"} にする。
// まとまりのパッケージの処理を束ねる型は、Unimplemented を、まとまりの処理より深い位置に埋め込む。
// そうすると、まとまりが作った操作はまとまりの処理が受け持ち、まだ作っていない操作だけがここに来る。
type Unimplemented struct{}

var _ gen.StrictServerInterface = Unimplemented{}

// VerifyTwoFactorAuth は、まだ作っていない操作である。
func (Unimplemented) VerifyTwoFactorAuth(context.Context, gen.VerifyTwoFactorAuthRequestObject) (gen.VerifyTwoFactorAuthResponseObject, error) {
	return nil, ErrNotImplemented
}

// ResendEmailVerification は、まだ作っていない操作である。
func (Unimplemented) ResendEmailVerification(context.Context, gen.ResendEmailVerificationRequestObject) (gen.ResendEmailVerificationResponseObject, error) {
	return nil, ErrNotImplemented
}

// ResendEmailVerificationForLogin は、まだ作っていない操作である。
func (Unimplemented) ResendEmailVerificationForLogin(context.Context, gen.ResendEmailVerificationForLoginRequestObject) (gen.ResendEmailVerificationForLoginResponseObject, error) {
	return nil, ErrNotImplemented
}

// VerifyEmail は、まだ作っていない操作である。
func (Unimplemented) VerifyEmail(context.Context, gen.VerifyEmailRequestObject) (gen.VerifyEmailResponseObject, error) {
	return nil, ErrNotImplemented
}

// Login は、まだ作っていない操作である。
func (Unimplemented) Login(context.Context, gen.LoginRequestObject) (gen.LoginResponseObject, error) {
	return nil, ErrNotImplemented
}

// Logout は、まだ作っていない操作である。
func (Unimplemented) Logout(context.Context, gen.LogoutRequestObject) (gen.LogoutResponseObject, error) {
	return nil, ErrNotImplemented
}

// StartOidcAuthorization は、まだ作っていない操作である。
func (Unimplemented) StartOidcAuthorization(context.Context, gen.StartOidcAuthorizationRequestObject) (gen.StartOidcAuthorizationResponseObject, error) {
	return nil, ErrNotImplemented
}

// HandleOidcCallback は、まだ作っていない操作である。
func (Unimplemented) HandleOidcCallback(context.Context, gen.HandleOidcCallbackRequestObject) (gen.HandleOidcCallbackResponseObject, error) {
	return nil, ErrNotImplemented
}

// ResetPassword は、まだ作っていない操作である。
func (Unimplemented) ResetPassword(context.Context, gen.ResetPasswordRequestObject) (gen.ResetPasswordResponseObject, error) {
	return nil, ErrNotImplemented
}

// RequestPasswordReset は、まだ作っていない操作である。
func (Unimplemented) RequestPasswordReset(context.Context, gen.RequestPasswordResetRequestObject) (gen.RequestPasswordResetResponseObject, error) {
	return nil, ErrNotImplemented
}

// VerifyPasswordResetToken は、まだ作っていない操作である。
func (Unimplemented) VerifyPasswordResetToken(context.Context, gen.VerifyPasswordResetTokenRequestObject) (gen.VerifyPasswordResetTokenResponseObject, error) {
	return nil, ErrNotImplemented
}

// RegisterUser は、まだ作っていない操作である。
func (Unimplemented) RegisterUser(context.Context, gen.RegisterUserRequestObject) (gen.RegisterUserResponseObject, error) {
	return nil, ErrNotImplemented
}

// RefreshToken は、まだ作っていない操作である。
func (Unimplemented) RefreshToken(context.Context, gen.RefreshTokenRequestObject) (gen.RefreshTokenResponseObject, error) {
	return nil, ErrNotImplemented
}

// ListCertificationNames は、まだ作っていない操作である。
func (Unimplemented) ListCertificationNames(context.Context, gen.ListCertificationNamesRequestObject) (gen.ListCertificationNamesResponseObject, error) {
	return nil, ErrNotImplemented
}

// ListResumes は、まだ作っていない操作である。
func (Unimplemented) ListResumes(context.Context, gen.ListResumesRequestObject) (gen.ListResumesResponseObject, error) {
	return nil, ErrNotImplemented
}

// CreateResume は、まだ作っていない操作である。
func (Unimplemented) CreateResume(context.Context, gen.CreateResumeRequestObject) (gen.CreateResumeResponseObject, error) {
	return nil, ErrNotImplemented
}

// RestoreResume は、まだ作っていない操作である。
func (Unimplemented) RestoreResume(context.Context, gen.RestoreResumeRequestObject) (gen.RestoreResumeResponseObject, error) {
	return nil, ErrNotImplemented
}

// DeleteResume は、まだ作っていない操作である。
func (Unimplemented) DeleteResume(context.Context, gen.DeleteResumeRequestObject) (gen.DeleteResumeResponseObject, error) {
	return nil, ErrNotImplemented
}

// GetResume は、まだ作っていない操作である。
func (Unimplemented) GetResume(context.Context, gen.GetResumeRequestObject) (gen.GetResumeResponseObject, error) {
	return nil, ErrNotImplemented
}

// BackupResume は、まだ作っていない操作である。
func (Unimplemented) BackupResume(context.Context, gen.BackupResumeRequestObject) (gen.BackupResumeResponseObject, error) {
	return nil, ErrNotImplemented
}

// UpdateResumeBasic は、まだ作っていない操作である。
func (Unimplemented) UpdateResumeBasic(context.Context, gen.UpdateResumeBasicRequestObject) (gen.UpdateResumeBasicResponseObject, error) {
	return nil, ErrNotImplemented
}

// CreateCareer は、まだ作っていない操作である。
func (Unimplemented) CreateCareer(context.Context, gen.CreateCareerRequestObject) (gen.CreateCareerResponseObject, error) {
	return nil, ErrNotImplemented
}

// DeleteCareer は、まだ作っていない操作である。
func (Unimplemented) DeleteCareer(context.Context, gen.DeleteCareerRequestObject) (gen.DeleteCareerResponseObject, error) {
	return nil, ErrNotImplemented
}

// UpdateCareer は、まだ作っていない操作である。
func (Unimplemented) UpdateCareer(context.Context, gen.UpdateCareerRequestObject) (gen.UpdateCareerResponseObject, error) {
	return nil, ErrNotImplemented
}

// CreateCertification は、まだ作っていない操作である。
func (Unimplemented) CreateCertification(context.Context, gen.CreateCertificationRequestObject) (gen.CreateCertificationResponseObject, error) {
	return nil, ErrNotImplemented
}

// DeleteCertification は、まだ作っていない操作である。
func (Unimplemented) DeleteCertification(context.Context, gen.DeleteCertificationRequestObject) (gen.DeleteCertificationResponseObject, error) {
	return nil, ErrNotImplemented
}

// UpdateCertification は、まだ作っていない操作である。
func (Unimplemented) UpdateCertification(context.Context, gen.UpdateCertificationRequestObject) (gen.UpdateCertificationResponseObject, error) {
	return nil, ErrNotImplemented
}

// ExportResume は、まだ作っていない操作である。
func (Unimplemented) ExportResume(context.Context, gen.ExportResumeRequestObject) (gen.ExportResumeResponseObject, error) {
	return nil, ErrNotImplemented
}

// ExportResumeWithSettings は、まだ作っていない操作である。
func (Unimplemented) ExportResumeWithSettings(context.Context, gen.ExportResumeWithSettingsRequestObject) (gen.ExportResumeWithSettingsResponseObject, error) {
	return nil, ErrNotImplemented
}

// CreatePortfolio は、まだ作っていない操作である。
func (Unimplemented) CreatePortfolio(context.Context, gen.CreatePortfolioRequestObject) (gen.CreatePortfolioResponseObject, error) {
	return nil, ErrNotImplemented
}

// DeletePortfolio は、まだ作っていない操作である。
func (Unimplemented) DeletePortfolio(context.Context, gen.DeletePortfolioRequestObject) (gen.DeletePortfolioResponseObject, error) {
	return nil, ErrNotImplemented
}

// UpdatePortfolio は、まだ作っていない操作である。
func (Unimplemented) UpdatePortfolio(context.Context, gen.UpdatePortfolioRequestObject) (gen.UpdatePortfolioResponseObject, error) {
	return nil, ErrNotImplemented
}

// CreateProject は、まだ作っていない操作である。
func (Unimplemented) CreateProject(context.Context, gen.CreateProjectRequestObject) (gen.CreateProjectResponseObject, error) {
	return nil, ErrNotImplemented
}

// DeleteProject は、まだ作っていない操作である。
func (Unimplemented) DeleteProject(context.Context, gen.DeleteProjectRequestObject) (gen.DeleteProjectResponseObject, error) {
	return nil, ErrNotImplemented
}

// UpdateProject は、まだ作っていない操作である。
func (Unimplemented) UpdateProject(context.Context, gen.UpdateProjectRequestObject) (gen.UpdateProjectResponseObject, error) {
	return nil, ErrNotImplemented
}

// CreateSelfPromotion は、まだ作っていない操作である。
func (Unimplemented) CreateSelfPromotion(context.Context, gen.CreateSelfPromotionRequestObject) (gen.CreateSelfPromotionResponseObject, error) {
	return nil, ErrNotImplemented
}

// DeleteSelfPromotion は、まだ作っていない操作である。
func (Unimplemented) DeleteSelfPromotion(context.Context, gen.DeleteSelfPromotionRequestObject) (gen.DeleteSelfPromotionResponseObject, error) {
	return nil, ErrNotImplemented
}

// UpdateSelfPromotion は、まだ作っていない操作である。
func (Unimplemented) UpdateSelfPromotion(context.Context, gen.UpdateSelfPromotionRequestObject) (gen.UpdateSelfPromotionResponseObject, error) {
	return nil, ErrNotImplemented
}

// CreateSnsPlatform は、まだ作っていない操作である。
func (Unimplemented) CreateSnsPlatform(context.Context, gen.CreateSnsPlatformRequestObject) (gen.CreateSnsPlatformResponseObject, error) {
	return nil, ErrNotImplemented
}

// DeleteSnsPlatform は、まだ作っていない操作である。
func (Unimplemented) DeleteSnsPlatform(context.Context, gen.DeleteSnsPlatformRequestObject) (gen.DeleteSnsPlatformResponseObject, error) {
	return nil, ErrNotImplemented
}

// UpdateSnsPlatform は、まだ作っていない操作である。
func (Unimplemented) UpdateSnsPlatform(context.Context, gen.UpdateSnsPlatformRequestObject) (gen.UpdateSnsPlatformResponseObject, error) {
	return nil, ErrNotImplemented
}

// ListSnsPlatformNames は、まだ作っていない操作である。
func (Unimplemented) ListSnsPlatformNames(context.Context, gen.ListSnsPlatformNamesRequestObject) (gen.ListSnsPlatformNamesResponseObject, error) {
	return nil, ErrNotImplemented
}

// ListTechStacks は、まだ作っていない操作である。
func (Unimplemented) ListTechStacks(context.Context, gen.ListTechStacksRequestObject) (gen.ListTechStacksResponseObject, error) {
	return nil, ErrNotImplemented
}

// DeleteUser は、まだ作っていない操作である。
func (Unimplemented) DeleteUser(context.Context, gen.DeleteUserRequestObject) (gen.DeleteUserResponseObject, error) {
	return nil, ErrNotImplemented
}

// GetUserInfo は、まだ作っていない操作である。
func (Unimplemented) GetUserInfo(context.Context, gen.GetUserInfoRequestObject) (gen.GetUserInfoResponseObject, error) {
	return nil, ErrNotImplemented
}

// UpdateUserInfo は、まだ作っていない操作である。
func (Unimplemented) UpdateUserInfo(context.Context, gen.UpdateUserInfoRequestObject) (gen.UpdateUserInfoResponseObject, error) {
	return nil, ErrNotImplemented
}

// RemoveAuthProvider は、まだ作っていない操作である。
func (Unimplemented) RemoveAuthProvider(context.Context, gen.RemoveAuthProviderRequestObject) (gen.RemoveAuthProviderResponseObject, error) {
	return nil, ErrNotImplemented
}

// SetEmailAndPassword は、まだ作っていない操作である。
func (Unimplemented) SetEmailAndPassword(context.Context, gen.SetEmailAndPasswordRequestObject) (gen.SetEmailAndPasswordResponseObject, error) {
	return nil, ErrNotImplemented
}

// SendAccountEmailVerification は、まだ作っていない操作である。
func (Unimplemented) SendAccountEmailVerification(context.Context, gen.SendAccountEmailVerificationRequestObject) (gen.SendAccountEmailVerificationResponseObject, error) {
	return nil, ErrNotImplemented
}

// ChangePassword は、まだ作っていない操作である。
func (Unimplemented) ChangePassword(context.Context, gen.ChangePasswordRequestObject) (gen.ChangePasswordResponseObject, error) {
	return nil, ErrNotImplemented
}
