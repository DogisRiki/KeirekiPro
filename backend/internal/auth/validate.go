package auth

import "strings"

// このファイルは、Java 版の認証の要求の型(presentation/auth/dto)の注釈を、操作ごとの検査の関数に写す。
// 検査の関数は、項目ごとに、注釈を書いた順に文言を集め、誤りがあれば入力の誤りの *Error を返す。誤りが無ければ nil を返す。
// 項目の名前は、Java 版の要求の型の項目の名前である。
//
// Go 版が受け取る値は、生成した要求の型の string なので、項目が無い要求と、空の文字列の項目を持つ要求を見分けない。
// どちらも空の文字列として検査する。Java 版は、項目が無いと null になり、@NotBlank のほかの注釈を当てない。

// Java 版の注釈の文言である。文言は Java 版と1文字も違わないようにする。
const (
	msgEmailRequired         = "メールアドレスは入力必須です。"
	msgEmailTooLong          = "メールアドレスは255文字以内で入力してください。"
	msgEmailInvalid          = "メールアドレスの形式が無効です。"
	msgUsernameRequired      = "ユーザー名は入力必須です。"
	msgUsernameTooLong       = "ユーザー名は50文字以内で入力してください。"
	msgPhraseRequired        = "パスワードは入力必須です。"
	msgPhraseLength          = "パスワードは8文字以上で、半角72文字以内で入力してください。全角の文字は1文字を半角3文字分として数えます。"
	msgPhrasePattern         = "パスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。"
	msgConfirmRequired       = "パスワード(確認)は入力必須です。"
	msgPhraseMismatch        = "パスワードとパスワード(確認)が一致していません。"
	msgNewPhraseRequired     = "新しいパスワードは入力必須です。"
	msgNewPhraseLength       = "新しいパスワードは8文字以上で、半角72文字以内で入力してください。全角の文字は1文字を半角3文字分として数えます。"
	msgNewPhrasePattern      = "新しいパスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。"
	msgNewConfirmRequired    = "新しいパスワード(確認)は入力必須です。"
	msgNewPhraseMismatch     = "新しいパスワードと新しいパスワード(確認)が一致していません。"
	msgVerifyValueRequired   = "トークンは入力必須です。"
	msgVerifyValueTooLong    = "トークンは2048文字以内で入力してください。"
	msgTwoFactorCodeRequired = "認証コードは入力必須です。"
	passwordMinLength        = 8
	passwordMaxUTF8Bytes     = 72
	emailMaxLength           = 255
	usernameMaxLength        = 50
	tokenMaxLength           = 2048
	emailLocalPartMaxLength  = 64
)

// fieldErrors は、項目ごとの文言を、注釈を書いた順に集める。
type fieldErrors map[string][]string

// check は、ok が偽のとき、項目 field に文言 message を足す。
func (f fieldErrors) check(field string, ok bool, message string) {
	if !ok {
		f[field] = append(f[field], message)
	}
}

// result は、文言が1つでもあれば入力の誤りを、無ければ nil を返す。
func (f fieldErrors) result() *Error {
	if len(f) == 0 {
		return nil
	}
	return errInvalidInput(f)
}

// ValidateLogin は、ログインの要求(Java 版の LoginRequest)を検査する。
func ValidateLogin(email, password string) *Error {
	f := fieldErrors{}
	f.check("email", notBlank(email), msgEmailRequired)
	f.check("password", notBlank(password), msgPhraseRequired)
	return f.result()
}

// ValidateResendEmailVerificationForLogin は、ログインの画面からの確認のメールの送り直しの要求
// (Java 版の ResendEmailVerificationForLoginRequest)を検査する。
func ValidateResendEmailVerificationForLogin(email, password string) *Error {
	return ValidateLogin(email, password)
}

// ValidateRegister は、新規の登録の要求(Java 版の UserRegistrationRequest)を検査する。
// パスワードが一致しない文言は、クラスに付けた @PasswordMatches を項目の注釈より先に書いてあるので、confirmPassword の先頭に置く。
func ValidateRegister(email, username, password, confirmPassword string) *Error {
	f := fieldErrors{}
	f.check("confirmPassword", password == confirmPassword, msgPhraseMismatch)
	f.check("email", notBlank(email), msgEmailRequired)
	f.check("email", utf16Len(email) <= emailMaxLength, msgEmailTooLong)
	f.check("email", isEmailFormat(email), msgEmailInvalid)
	f.check("username", notBlank(username), msgUsernameRequired)
	f.check("username", utf16Len(username) <= usernameMaxLength, msgUsernameTooLong)
	f.check("password", notBlank(password), msgPhraseRequired)
	f.check("password", utf16Len(password) >= passwordMinLength, msgPhraseLength)
	f.check("password", len(password) <= passwordMaxUTF8Bytes, msgPhraseLength)
	f.check("password", passwordPatternOK(password), msgPhrasePattern)
	f.check("confirmPassword", notBlank(confirmPassword), msgConfirmRequired)
	return f.result()
}

// ValidateEmailVerificationToken は、メールアドレスの確認と確認のメールの送り直しの要求
// (Java 版の EmailVerificationTokenRequest)を検査する。
func ValidateEmailVerificationToken(token string) *Error {
	f := fieldErrors{}
	f.check("token", notBlank(token), msgVerifyValueRequired)
	f.check("token", utf16Len(token) <= tokenMaxLength, msgVerifyValueTooLong)
	return f.result()
}

// ValidateTwoFactor は、2段階認証の確認のコードの要求(Java 版の TwoFactorAuthRequest)を検査する。
func ValidateTwoFactor(code string) *Error {
	f := fieldErrors{}
	f.check("code", notBlank(code), msgTwoFactorCodeRequired)
	return f.result()
}

// ValidatePasswordResetRequest は、パスワードの再設定の申し込みの要求(Java 版の RequestPasswordResetRequest)を検査する。
func ValidatePasswordResetRequest(email string) *Error {
	f := fieldErrors{}
	f.check("email", notBlank(email), msgEmailRequired)
	f.check("email", isEmailFormat(email), msgEmailInvalid)
	return f.result()
}

// ValidateResetPassword は、パスワードの再設定の要求(Java 版の ResetPasswordRequest)を検査する。
// 再設定の値(token)は、Java 版の要求の型が注釈を持たないので、検査しない。
func ValidateResetPassword(password, confirmPassword string) *Error {
	f := fieldErrors{}
	f.check("confirmPassword", password == confirmPassword, msgNewPhraseMismatch)
	f.check("password", notBlank(password), msgNewPhraseRequired)
	f.check("password", utf16Len(password) >= passwordMinLength, msgNewPhraseLength)
	f.check("password", len(password) <= passwordMaxUTF8Bytes, msgNewPhraseLength)
	f.check("password", passwordPatternOK(password), msgNewPhrasePattern)
	f.check("confirmPassword", notBlank(confirmPassword), msgNewConfirmRequired)
	return f.result()
}

// notBlank は、s が空白(unicode.IsSpace)でない字を1つ以上含むかを返す。
func notBlank(s string) bool {
	return strings.TrimSpace(s) != ""
}

// utf16Len は、Java の String.length() と同じく、s の UTF-16 の単位の数を返す。
func utf16Len(s string) int {
	n := 0
	for _, r := range s {
		n++
		if r > 0xFFFF {
			n++
		}
	}
	return n
}

// passwordPatternOK は、Java 版の @Pattern("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).+$") と同じく、s が英小文字と英大文字と
// 数字(ASCII)をそれぞれ1文字以上含み、行の終わりの文字を含まないかを返す。Java の「.」は行の終わりの文字に当たらず、
// @Pattern は値の全体が当たることを求めるので、行の終わりの文字を1つでも含む値は当たらない。
func passwordPatternOK(s string) bool {
	if strings.ContainsAny(s, "\n\r\u0085\u2028\u2029") {
		return false
	}
	return strings.ContainsAny(s, "abcdefghijklmnopqrstuvwxyz") &&
		strings.ContainsAny(s, "ABCDEFGHIJKLMNOPQRSTUVWXYZ") &&
		strings.ContainsAny(s, "0123456789")
}
