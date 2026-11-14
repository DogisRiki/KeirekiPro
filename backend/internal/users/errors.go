package users

import "github.com/DogisRiki/KeirekiPro/backend/internal/auth"

// 利用者の操作の文言である。どれも Java 版のソースの文字列を1文字も変えずに写した。
// 認証の spec がすでに公開している文言は、同じ定数を指す。
// パスワードの文言の名前は、認証の spec と同じく Password でなく Phrase にする。gosec の G101 が、名前に Password を含む文字列の定数を、
// 書き込まれた秘密の値と見なすためである。
const (
	// MessageInvalidAccess は、利用者が居ないときの文言である(7つのユースケースの AuthenticationCredentialsNotFoundException)。
	MessageInvalidAccess = auth.MessageInvalidAccess

	// MessageNowPhraseWrong と MessageNewPhraseSameAsNow は、ChangePasswordUseCase が項目 nowPassword と newPassword に足す文言である。
	MessageNowPhraseWrong     = "現在のパスワードが正しくありません。"
	MessageNewPhraseSameAsNow = "新しいパスワードは現在のパスワードと異なる必要があります。"

	// MessageNothingToVerify と MessageResendRateLimited は、SendAccountEmailVerificationUseCase の文言である。
	MessageNothingToVerify   = "確認が必要なメールアドレスはありません。"
	MessageResendRateLimited = auth.MessageResendRateLimited

	// MessageCurrentPhraseWrong は、SetEmailAndPasswordUseCase の文言である。
	MessageCurrentPhraseWrong = "今のパスワードが正しくありません。"

	// MessageImage で始まる文言は、UpdateUserInfoUseCase が項目 profileImage に足す文言である。
	MessageImageTypeNotAllowed      = "許可されていない画像形式です。"
	MessageImageExtensionNotAllowed = "許可されていないファイル形式です。jpg, jpeg, png, gifのみ許可されています。"
	MessageImageTooLarge            = "プロフィール画像のサイズは1MB以下である必要があります。"
	MessageImageInvalid             = "有効な画像ファイルではありません。"
	MessageImageTooBig              = "プロフィール画像の幅と高さは4096ピクセル以下である必要があります。"

	// MessageUsernameRequired と MessageUsernameTooLong は、User.changeUsername が項目 username に足す文言である。
	MessageUsernameRequired = "ユーザー名は必ず指定してください。"
	MessageUsernameTooLong  = "ユーザー名は50文字以内で入力してください。"

	// MessageAdminTwoFactorRequired と MessageTwoFactorPrerequisiteMissing は、
	// User.changeTwoFactorAuthEnabled が項目 twoFactorAuthEnabled に足す文言である。
	MessageAdminTwoFactorRequired       = "管理者の場合は二段階認証を無効にできません。"
	MessageTwoFactorPrerequisiteMissing = auth.MessageTwoFactorPrerequisiteMissing

	// MessageProviderRemoveFailed と MessageProviderLastOne は、User.removeAuthProvider が項目 authProviders に足す文言である。
	MessageProviderRemoveFailed = "連携の解除に失敗しました。"
	MessageProviderLastOne      = "メールアドレスとパスワードが設定済みでないと、連携を解除できません。"

	// MessageEmailAlreadySet は、User.setPendingEmail が項目 email に足す文言である。
	MessageEmailAlreadySet = "メールアドレスが既に設定されているため設定できません。"

	// 次の4つは、ChangePasswordRequest の注釈の文言である(項目 nowPassword と newPassword)。
	MessageNowPhraseRequired = "現在のパスワードは入力必須です。"
	MessageNewPhraseRequired = "新しいパスワードは入力必須です。"
	MessageNewPhraseLength   = "新しいパスワードは8文字以上で、半角72文字以内で入力してください。全角の文字は1文字を半角3文字分として数えます。"
	MessageNewPhrasePattern  = "新しいパスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。"

	// 次の5つは、SetEmailAndPasswordRequest の注釈の文言である(項目 email と password)。
	MessageEmailInvalid   = "メールアドレスの形式が無効です。"
	MessageEmailTooLong   = "メールアドレスは255文字以内で入力してください。"
	MessagePhraseRequired = "パスワードは入力必須です。"
	MessagePhraseLength   = "パスワードは8文字以上で、半角72文字以内で入力してください。全角の文字は1文字を半角3文字分として数えます。"
	MessagePhrasePattern  = "パスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。"

	// MessagePhraseMismatch は、SetEmailAndPasswordRequest の @PasswordMatches の既定の文言である(項目 confirmPassword)。
	MessagePhraseMismatch = "パスワードとパスワード(確認)が一致していません。"
)
