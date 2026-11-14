package users

import "testing"

// TestErrors_MessagesMatchJava は、利用者の操作の文言の定数が、Java 版のソースの文字列と1文字も違わないことを確かめる。
// want は、Java 版のソースの文字列を写したものである。コメントに、写した元のクラスと項目を書く。
func TestErrors_MessagesMatchJava(t *testing.T) {
	tests := []struct {
		name string
		got  string
		want string
	}{
		// 7つのユースケースの AuthenticationCredentialsNotFoundException
		{"MessageInvalidAccess", MessageInvalidAccess, "不正なアクセスです。"},
		// ChangePasswordUseCase(項目 nowPassword と newPassword)
		{"MessageNowPhraseWrong", MessageNowPhraseWrong, "現在のパスワードが正しくありません。"},
		{"MessageNewPhraseSameAsNow", MessageNewPhraseSameAsNow, "新しいパスワードは現在のパスワードと異なる必要があります。"},
		// SendAccountEmailVerificationUseCase
		{"MessageNothingToVerify", MessageNothingToVerify, "確認が必要なメールアドレスはありません。"},
		{"MessageResendRateLimited", MessageResendRateLimited, "確認のメールは1分に1回まで送れます。少し待ってからもう一度お試しください。"},
		// SetEmailAndPasswordUseCase
		{"MessageCurrentPhraseWrong", MessageCurrentPhraseWrong, "今のパスワードが正しくありません。"},
		// UpdateUserInfoUseCase(項目 profileImage)
		{"MessageImageTypeNotAllowed", MessageImageTypeNotAllowed, "許可されていない画像形式です。"},
		{"MessageImageExtensionNotAllowed", MessageImageExtensionNotAllowed, "許可されていないファイル形式です。jpg, jpeg, png, gifのみ許可されています。"},
		{"MessageImageTooLarge", MessageImageTooLarge, "プロフィール画像のサイズは1MB以下である必要があります。"},
		{"MessageImageInvalid", MessageImageInvalid, "有効な画像ファイルではありません。"},
		{"MessageImageTooBig", MessageImageTooBig, "プロフィール画像の幅と高さは4096ピクセル以下である必要があります。"},
		// User.changeUsername(項目 username)
		{"MessageUsernameRequired", MessageUsernameRequired, "ユーザー名は必ず指定してください。"},
		{"MessageUsernameTooLong", MessageUsernameTooLong, "ユーザー名は50文字以内で入力してください。"},
		// User.changeTwoFactorAuthEnabled(項目 twoFactorAuthEnabled)
		{"MessageAdminTwoFactorRequired", MessageAdminTwoFactorRequired, "管理者の場合は二段階認証を無効にできません。"},
		{"MessageTwoFactorPrerequisiteMissing", MessageTwoFactorPrerequisiteMissing, "メールアドレスとパスワードが未設定の場合は二段階認証を有効にできません。"},
		// User.removeAuthProvider(項目 authProviders)
		{"MessageProviderRemoveFailed", MessageProviderRemoveFailed, "連携の解除に失敗しました。"},
		{"MessageProviderLastOne", MessageProviderLastOne, "メールアドレスとパスワードが設定済みでないと、連携を解除できません。"},
		// User.setPendingEmail(項目 email)
		{"MessageEmailAlreadySet", MessageEmailAlreadySet, "メールアドレスが既に設定されているため設定できません。"},
		// ChangePasswordRequest の注釈(項目 nowPassword と newPassword)
		{"MessageNowPhraseRequired", MessageNowPhraseRequired, "現在のパスワードは入力必須です。"},
		{"MessageNewPhraseRequired", MessageNewPhraseRequired, "新しいパスワードは入力必須です。"},
		{"MessageNewPhraseLength", MessageNewPhraseLength, "新しいパスワードは8文字以上で、半角72文字以内で入力してください。全角の文字は1文字を半角3文字分として数えます。"},
		{"MessageNewPhrasePattern", MessageNewPhrasePattern, "新しいパスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。"},
		// SetEmailAndPasswordRequest の注釈(項目 email と password)と、@PasswordMatches の既定の文言(項目 confirmPassword)
		{"MessageEmailInvalid", MessageEmailInvalid, "メールアドレスの形式が無効です。"},
		{"MessageEmailTooLong", MessageEmailTooLong, "メールアドレスは255文字以内で入力してください。"},
		{"MessagePhraseRequired", MessagePhraseRequired, "パスワードは入力必須です。"},
		{"MessagePhraseLength", MessagePhraseLength, "パスワードは8文字以上で、半角72文字以内で入力してください。全角の文字は1文字を半角3文字分として数えます。"},
		{"MessagePhrasePattern", MessagePhrasePattern, "パスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。"},
		{"MessagePhraseMismatch", MessagePhraseMismatch, "パスワードとパスワード(確認)が一致していません。"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.got != tt.want {
				t.Errorf("%s = %q, want %q", tt.name, tt.got, tt.want)
			}
		})
	}
}
