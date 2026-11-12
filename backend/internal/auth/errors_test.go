package auth

import (
	"errors"
	"fmt"
	"reflect"
	"testing"
)

// TestError_MessagesMatchJava は、文言の定数が Java 版の文言と1文字も違わないことを確かめる。
// 500 と 403 の文言は、置き換えの spec の土台(internal/httpapi/middleware の MessageUnexpected と
// MessageForbidden)と同じでなければならない。internal/auth は依存の向きの決まりで
// internal/httpapi/middleware を読めないので、土台と同じ文字列をここに書いて比べる。
func TestError_MessagesMatchJava(t *testing.T) {
	tests := []struct {
		name string
		got  string
		want string
	}{
		// AppExceptionHandler
		{"MessageInvalidInput", MessageInvalidInput, "入力エラーがあります。"},
		{"MessageUnauthenticated", MessageUnauthenticated, "認証に失敗しました。"},
		{"MessageEmailNotVerified", MessageEmailNotVerified, "メールアドレスの確認が済んでいません。"},
		{"MessageUnexpected", MessageUnexpected, "予期せぬエラーが発生しました。"},
		// SecurityConfig の accessDeniedHandler
		{"MessageForbidden", MessageForbidden, "アクセス権限がありません。"},
		// LoginUseCase と ResendEmailVerificationForLoginUseCase
		{"MessageLoginFailed", MessageLoginFailed, "メールアドレスまたはパスワードが正しくありません。"},
		// ResendEmailVerificationUseCase と ResendEmailVerificationForLoginUseCase
		{"MessageResendRateLimited", MessageResendRateLimited, "確認のメールは1分に1回まで送れます。少し待ってからもう一度お試しください。"},
		{"MessageNotResendable", MessageNotResendable, "このリンクでは確認のメールを送り直せません。"},
		// EmailVerificationCompletion
		{"MessageInvalidVerificationLink", MessageInvalidVerificationLink, "確認のリンクが無効です。"},
		// VerifyPasswordResetTokenUseCase と ResetPasswordUseCase
		{"MessageInvalidResetLink", MessageInvalidResetLink, "リセットリンクが無効または期限切れです。もう一度最初からお試しください。"},
		{"MessageInvalidAccess", MessageInvalidAccess, "不正なアクセスです。"},
		// TwoFactorAuthController と TwoFactorAuthVerifyUseCase
		{"MessageInvalidTwoFactorSession", MessageInvalidTwoFactorSession, "認証セッションが無効または期限切れです。もう一度最初からお試しください。"},
		{"MessageInvalidTwoFactorCode", MessageInvalidTwoFactorCode, "認証コードが無効または期限切れです。もう一度最初からお試しください。"},
		{"MessageTwoFactorAttemptsExceeded", MessageTwoFactorAttemptsExceeded, "試行回数の上限に達しました。もう一度最初からお試しください。"},
		{"MessageUserInfoUnavailable", MessageUserInfoUnavailable, "ユーザー情報の取得に失敗しました。"},
		// User.reconstruct
		{"MessageTwoFactorPrerequisiteMissing", MessageTwoFactorPrerequisiteMissing, "メールアドレスとパスワードが未設定の場合は二段階認証を有効にできません。"},
		{"MessageAdminNeedsTwoFactor", MessageAdminNeedsTwoFactor, "管理者の場合は二段階認証が必須です。"},
		// UnverifiedEmailAccountUseCaseException と OidcCallbackController
		{"MessageOIDCUnverifiedAccount", MessageOIDCUnverifiedAccount, "メールアドレスの確認が済んでいないアカウントには外部連携を結び付けられません。"},
		{"MessageOIDCUserInfoFailed", MessageOIDCUserInfoFailed, "ユーザー情報の取得に失敗しました。しばらく時間を置いてから再度お試しください。"},
		{"MessageOIDCFailed", MessageOIDCFailed, "認証に失敗しました。しばらく時間を置いてから再度お試しください。"},
		// EmailNotVerifiedUseCaseException.Kind
		{"KindPendingRegistration", string(KindPendingRegistration), "PENDING_REGISTRATION"},
		{"KindUnverifiedAccountEmail", string(KindUnverifiedAccountEmail), "UNVERIFIED_ACCOUNT_EMAIL"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.got != tt.want {
				t.Errorf("%s = %q, want %q", tt.name, tt.got, tt.want)
			}
		})
	}
}

// TestError_LoginFailureMessageIsSingle は、アカウントが無いときとパスワードが違うときに、
// ログインの操作が返す誤りが、状態の番号も文言も同じ1つの形であることを確かめる。
func TestError_LoginFailureMessageIsSingle(t *testing.T) {
	noAccount := errInvalidCredentials()
	wrongPassword := errInvalidCredentials()
	if !reflect.DeepEqual(noAccount, wrongPassword) {
		t.Fatalf("errInvalidCredentials() が呼ぶたびに違う: %+v と %+v", noAccount, wrongPassword)
	}
	want := &Error{Status: 400, Message: "メールアドレスまたはパスワードが正しくありません。", Errors: map[string][]string{}}
	if !reflect.DeepEqual(noAccount, want) {
		t.Errorf("errInvalidCredentials() = %+v, want %+v", noAccount, want)
	}
}

// TestError_Shapes は、設計の Error の節の5つの答えの形を、Error の項目で表せることを確かめる。
func TestError_Shapes(t *testing.T) {
	tests := []struct {
		name string
		got  *Error
		want *Error
	}{
		{
			name: "業務の決まりで断る",
			got:  errBusiness("確認のリンクが無効です。"),
			want: &Error{Status: 400, Message: "確認のリンクが無効です。", Errors: map[string][]string{}},
		},
		{
			name: "確認の済んでいないメールアドレス",
			got:  errEmailNotVerified(KindPendingRegistration),
			want: &Error{Status: 409, Message: "メールアドレスの確認が済んでいません。", Errors: map[string][]string{}, Kind: KindPendingRegistration},
		},
		{
			name: "入力の誤り",
			got:  errInvalidInput(map[string][]string{"email": {"メールアドレスは入力必須です。"}}),
			want: &Error{Status: 400, Message: "入力エラーがあります。", Errors: map[string][]string{"email": {"メールアドレスは入力必須です。"}}},
		},
		{
			name: "ログインを続けるための値が無いか無効",
			got:  errUnauthenticated(),
			want: &Error{Status: 401, Message: "認証に失敗しました。", Errors: map[string][]string{}},
		},
		{
			name: "操作の相手の利用者が居ない",
			got:  errCredentialsNotFound("不正なアクセスです。"),
			want: &Error{Status: 401, Message: "不正なアクセスです。", Errors: map[string][]string{}, ClearSession: true},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if !reflect.DeepEqual(tt.got, tt.want) {
				t.Errorf("got %+v, want %+v", tt.got, tt.want)
			}
		})
	}
}

// TestError_UnwrapsWithErrorsAs は、包まれた *Error を errors.As で取り出せることと、
// Error() が文言を返すことを確かめる。認証の受け口は、この取り出し方で本文を書く。
func TestError_UnwrapsWithErrorsAs(t *testing.T) {
	wrapped := fmt.Errorf("ログイン: %w", errInvalidCredentials())
	var e *Error
	if !errors.As(wrapped, &e) {
		t.Fatalf("errors.As が *Error を取り出せない: %v", wrapped)
	}
	if e.Error() != MessageLoginFailed {
		t.Errorf("Error() = %q, want %q", e.Error(), MessageLoginFailed)
	}
}
