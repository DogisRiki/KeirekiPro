package users

import "github.com/DogisRiki/KeirekiPro/backend/internal/auth"

// 要求の型の注釈の値である。認証の spec の値と同じだが、認証のパッケージは公開していないので、ここに写す。
const (
	// phraseMinLength は、@Size(min = 8) の、パスワードの UTF-16 で数えた長さの下限である。
	phraseMinLength = 8
	// phraseMaxUTF8Bytes は、@MaxUtf8Bytes(72) の、パスワードの UTF-8 で数えたバイト数の上限である。
	phraseMaxUTF8Bytes = 72
	// emailMaxLength は、@Size(max = 255) の、メールアドレスの UTF-16 で数えた長さの上限である。
	emailMaxLength = 255
)

// ValidateChangePassword は、パスワードの変更の要求(Java 版の ChangePasswordRequest)を検査する。
// 1つの項目の文言は、認証の spec と同じく、注釈の順(入力必須、長さの下限、バイト数の上限、形)に並べる。
func ValidateChangePassword(nowPassword, newPassword string) *auth.Error {
	f := auth.FieldErrors{}
	f.Check("nowPassword", auth.NotBlank(nowPassword), MessageNowPhraseRequired)
	checkPhrase(f, "newPassword", newPassword, MessageNewPhraseRequired, MessageNewPhraseLength, MessageNewPhrasePattern)
	return f.Result()
}

// ValidateSetEmailAndPassword は、メールアドレスとパスワードの設定の要求(Java 版の SetEmailAndPasswordRequest)を検査する。
//   - email が nil なら検査しない。Java 版の @Size と @Email は null を通すためである。@Email は空の文字列も通す
//   - confirmPassword が nil なら、一致を検査しない。Java 版の @PasswordMatches は、確認が null のとき通すためである
//
// 一致の文言を最初に足すのは、認証の spec の ValidateRegister と同じ順にするためである。
func ValidateSetEmailAndPassword(email *string, password string, confirmPassword *string) *auth.Error {
	f := auth.FieldErrors{}
	if confirmPassword != nil {
		f.Check("confirmPassword", *confirmPassword == password, MessagePhraseMismatch)
	}
	if email != nil {
		f.Check("email", auth.UTF16Len(*email) <= emailMaxLength, MessageEmailTooLong)
		f.Check("email", auth.IsEmailLikeHibernate(*email), MessageEmailInvalid)
	}
	checkPhrase(f, "password", password, MessagePhraseRequired, MessagePhraseLength, MessagePhrasePattern)
	return f.Result()
}

// checkPhrase は、パスワードの項目 field を、@NotBlank、@Size(min = 8)、@MaxUtf8Bytes(72)、@Pattern の順に検査する。
// 8文字より短いことと72バイトを超えることは同時には起きないので、長さの文言が2つ並ぶことは無い。
func checkPhrase(f auth.FieldErrors, field, value, required, length, pattern string) {
	f.Check(field, auth.NotBlank(value), required)
	f.Check(field, auth.UTF16Len(value) >= phraseMinLength, length)
	f.Check(field, len(value) <= phraseMaxUTF8Bytes, length)
	f.Check(field, auth.PasswordPatternOK(value), pattern)
}
