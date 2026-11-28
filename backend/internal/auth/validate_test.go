package auth

import (
	"reflect"
	"strings"
	"testing"
)

// ch は、コードポイント r の1文字の文字列を返す。見えない文字をテストの中で読めるように書くために使う。
func ch(r rune) string {
	return string(r)
}

// validPhrase は、パスワードの検査をすべて通る値である。
const validPhrase = "Abcdefg1"

func TestValidate_Boundaries(t *testing.T) {
	type fields = map[string][]string
	// emailOf は、長さが n の、形の正しいメールアドレスを返す。前の部分は64文字にし、後ろの部分は63文字までのラベルを「.」でつなぐ。後ろの部分は253文字を超えない。
	emailOf := func(n int) string {
		domain := strings.Repeat("c", 63) + "." + strings.Repeat("c", 63) + "."
		return strings.Repeat("a", 64) + "@" + domain + strings.Repeat("d", n-65-len(domain))
	}
	tests := []struct {
		name string
		got  *Error
		want fields
	}{
		// ログイン
		{"ログイン: 正しい値", ValidateLogin("user@example.com", "x"), nil},
		{"ログイン: 空", ValidateLogin("", ""), fields{"email": {msgEmailRequired}, "password": {msgPhraseRequired}}},
		{"ログイン: 半角の空白とタブだけ", ValidateLogin(" \t", "\n\r"), fields{"email": {msgEmailRequired}, "password": {msgPhraseRequired}}},
		{"ログイン: 全角の空白と行の区切りだけ", ValidateLogin(ch(0x3000), ch(0x2028)+ch(0x1680)), fields{"email": {msgEmailRequired}, "password": {msgPhraseRequired}}},
		// 空白だけかは unicode.IsSpace で決める(変えた動きの一覧の CB-118)。
		{"ログイン: 改行させない空白と次の行の字だけ", ValidateLogin(ch(0x00A0), ch(0x2007)+ch(0x202F)+ch(0x85)), fields{"email": {msgEmailRequired}, "password": {msgPhraseRequired}}},
		{"ログイン: 情報の区切りの制御の字は空白でない", ValidateLogin(ch(0x1C), ch(0x1F)), nil},
		{"ログイン: メールアドレスの形は検査しない", ValidateLogin("bad", "x"), nil},
		{"確認のメールの送り直し(ログインの画面): 空", ValidateResendEmailVerificationForLogin("", " "), fields{"email": {msgEmailRequired}, "password": {msgPhraseRequired}}},
		{"確認のメールの送り直し(ログインの画面): 正しい値", ValidateResendEmailVerificationForLogin("user@example.com", "x"), nil},

		// 新規の登録
		{"登録: 正しい値", ValidateRegister("user@example.com", "taro", validPhrase, validPhrase), nil},
		{"登録: 空", ValidateRegister("", "", "", ""), fields{
			"email":           {msgEmailRequired},
			"username":        {msgUsernameRequired},
			"password":        {msgPhraseRequired, msgPhraseLength, msgPhrasePattern},
			"confirmPassword": {msgConfirmRequired},
		}},
		{"登録: 空白だけ", ValidateRegister(" ", ch(0x3000), "        ", "        "), fields{
			"email":           {msgEmailRequired, msgEmailInvalid},
			"username":        {msgUsernameRequired},
			"password":        {msgPhraseRequired, msgPhrasePattern},
			"confirmPassword": {msgConfirmRequired},
		}},
		{"登録: ユーザー名が50文字", ValidateRegister("user@example.com", strings.Repeat("a", 50), validPhrase, validPhrase), nil},
		{"登録: ユーザー名が51文字", ValidateRegister("user@example.com", strings.Repeat("a", 51), validPhrase, validPhrase), fields{"username": {msgUsernameTooLong}}},
		{"登録: ユーザー名が全角の50文字", ValidateRegister("user@example.com", strings.Repeat("あ", 50), validPhrase, validPhrase), nil},
		{"登録: ユーザー名が全角の51文字", ValidateRegister("user@example.com", strings.Repeat("あ", 51), validPhrase, validPhrase), fields{"username": {msgUsernameTooLong}}},
		{"登録: ユーザー名が基本多言語面の外の25文字(UTF-16 で50)", ValidateRegister("user@example.com", strings.Repeat(ch(0x1F600), 25), validPhrase, validPhrase), nil},
		{"登録: ユーザー名が基本多言語面の外の26文字(UTF-16 で52)", ValidateRegister("user@example.com", strings.Repeat(ch(0x1F600), 26), validPhrase, validPhrase), fields{"username": {msgUsernameTooLong}}},
		{"登録: メールアドレスが255文字", ValidateRegister(emailOf(255), "taro", validPhrase, validPhrase), nil},
		{"登録: メールアドレスが256文字", ValidateRegister(emailOf(256), "taro", validPhrase, validPhrase), fields{"email": {msgEmailTooLong}}},
		{"登録: メールアドレスの形が誤り", ValidateRegister("a@", "taro", validPhrase, validPhrase), fields{"email": {msgEmailInvalid}}},
		{"登録: パスワードが7文字", ValidateRegister("user@example.com", "taro", "Abcdef1", "Abcdef1"), fields{"password": {msgPhraseLength}}},
		{"登録: パスワードが全角を含む8文字", ValidateRegister("user@example.com", "taro", "Ab1あああああ", "Ab1あああああ"), nil},
		{"登録: パスワードが72バイト", ValidateRegister("user@example.com", "taro", "Ab1"+strings.Repeat("a", 69), "Ab1"+strings.Repeat("a", 69)), nil},
		{"登録: パスワードが73バイト", ValidateRegister("user@example.com", "taro", "Ab1"+strings.Repeat("a", 70), "Ab1"+strings.Repeat("a", 70)), fields{"password": {msgPhraseLength}}},
		{"登録: パスワードが全角で72バイト", ValidateRegister("user@example.com", "taro", "Ab1"+strings.Repeat("あ", 23), "Ab1"+strings.Repeat("あ", 23)), nil},
		{"登録: パスワードが全角で73バイト", ValidateRegister("user@example.com", "taro", "Ab1a"+strings.Repeat("あ", 23), "Ab1a"+strings.Repeat("あ", 23)), fields{"password": {msgPhraseLength}}},
		{"登録: パスワードが全角で75バイト", ValidateRegister("user@example.com", "taro", "Ab1"+strings.Repeat("あ", 24), "Ab1"+strings.Repeat("あ", 24)), fields{"password": {msgPhraseLength}}},
		{"登録: パスワードが改行を含む", ValidateRegister("user@example.com", "taro", validPhrase+"\n", validPhrase+"\n"), fields{"password": {msgPhrasePattern}}},
		{"登録: パスワードが復帰を含む", ValidateRegister("user@example.com", "taro", "\r"+validPhrase, "\r"+validPhrase), fields{"password": {msgPhrasePattern}}},
		{"登録: パスワードが次の行の文字を含む", ValidateRegister("user@example.com", "taro", validPhrase+ch(0x85), validPhrase+ch(0x85)), fields{"password": {msgPhrasePattern}}},
		{"登録: パスワードが行の区切りを含む", ValidateRegister("user@example.com", "taro", validPhrase+ch(0x2028), validPhrase+ch(0x2028)), fields{"password": {msgPhrasePattern}}},
		{"登録: パスワードが段落の区切りを含む", ValidateRegister("user@example.com", "taro", validPhrase+ch(0x2029), validPhrase+ch(0x2029)), fields{"password": {msgPhrasePattern}}},
		{"登録: パスワードがタブを含む", ValidateRegister("user@example.com", "taro", validPhrase+"\t", validPhrase+"\t"), nil},
		{"登録: パスワードに英小文字が無い", ValidateRegister("user@example.com", "taro", "ABCDEFG1", "ABCDEFG1"), fields{"password": {msgPhrasePattern}}},
		{"登録: パスワードに英大文字が無い", ValidateRegister("user@example.com", "taro", "abcdefg1", "abcdefg1"), fields{"password": {msgPhrasePattern}}},
		{"登録: パスワードに数字が無い", ValidateRegister("user@example.com", "taro", "Abcdefgh", "Abcdefgh"), fields{"password": {msgPhrasePattern}}},
		{"登録: パスワードの数字が全角", ValidateRegister("user@example.com", "taro", "Abcdefg１", "Abcdefg１"), fields{"password": {msgPhrasePattern}}},
		{"登録: パスワードの英字が全角", ValidateRegister("user@example.com", "taro", "ａＢcdefg1", "ａＢcdefg1"), fields{"password": {msgPhrasePattern}}},
		{"登録: パスワードが一致しない", ValidateRegister("user@example.com", "taro", validPhrase, validPhrase+"x"), fields{"confirmPassword": {msgPhraseMismatch}}},
		{"登録: 確認のパスワードが空", ValidateRegister("user@example.com", "taro", validPhrase, ""), fields{"confirmPassword": {msgPhraseMismatch, msgConfirmRequired}}},

		// メールアドレスの確認と確認のメールの送り直し
		{"確認の値: 正しい値", ValidateEmailVerificationToken("token"), nil},
		{"確認の値: 空", ValidateEmailVerificationToken(""), fields{"token": {msgVerifyValueRequired}}},
		{"確認の値: 空白だけ", ValidateEmailVerificationToken(" " + ch(0x3000)), fields{"token": {msgVerifyValueRequired}}},
		{"確認の値: 2048文字", ValidateEmailVerificationToken(strings.Repeat("t", 2048)), nil},
		{"確認の値: 2049文字", ValidateEmailVerificationToken(strings.Repeat("t", 2049)), fields{"token": {msgVerifyValueTooLong}}},
		{"確認の値: 全角の2049文字", ValidateEmailVerificationToken(strings.Repeat("あ", 2049)), fields{"token": {msgVerifyValueTooLong}}},
		{"確認の値: 空白の2049文字", ValidateEmailVerificationToken(strings.Repeat(" ", 2049)), fields{"token": {msgVerifyValueRequired, msgVerifyValueTooLong}}},

		// 2段階認証
		{"2段階認証: 正しい値", ValidateTwoFactor("123456"), nil},
		{"2段階認証: 空", ValidateTwoFactor(""), fields{"code": {msgTwoFactorCodeRequired}}},
		{"2段階認証: 空白だけ", ValidateTwoFactor(" \t"), fields{"code": {msgTwoFactorCodeRequired}}},

		// パスワードの再設定の申し込み
		{"再設定の申し込み: 正しい値", ValidatePasswordResetRequest("user@example.com"), nil},
		{"再設定の申し込み: 空", ValidatePasswordResetRequest(""), fields{"email": {msgEmailRequired}}},
		{"再設定の申し込み: 空白だけ", ValidatePasswordResetRequest(" "), fields{"email": {msgEmailRequired, msgEmailInvalid}}},
		{"再設定の申し込み: 形が誤り", ValidatePasswordResetRequest("user"), fields{"email": {msgEmailInvalid}}},
		{"再設定の申し込み: 長さは検査しない", ValidatePasswordResetRequest(emailOf(256)), nil},

		// パスワードの再設定
		{"再設定: 正しい値", ValidateResetPassword(validPhrase, validPhrase), nil},
		{"再設定: 空", ValidateResetPassword("", ""), fields{
			"password":        {msgNewPhraseRequired, msgNewPhraseLength, msgNewPhrasePattern},
			"confirmPassword": {msgNewConfirmRequired},
		}},
		{"再設定: 7文字", ValidateResetPassword("Abcdef1", "Abcdef1"), fields{"password": {msgNewPhraseLength}}},
		{"再設定: 72バイト", ValidateResetPassword("Ab1"+strings.Repeat("a", 69), "Ab1"+strings.Repeat("a", 69)), nil},
		{"再設定: 73バイト", ValidateResetPassword("Ab1"+strings.Repeat("a", 70), "Ab1"+strings.Repeat("a", 70)), fields{"password": {msgNewPhraseLength}}},
		{"再設定: 全角で75バイト", ValidateResetPassword("Ab1"+strings.Repeat("あ", 24), "Ab1"+strings.Repeat("あ", 24)), fields{"password": {msgNewPhraseLength}}},
		{"再設定: 改行を含む", ValidateResetPassword(validPhrase+"\n", validPhrase+"\n"), fields{"password": {msgNewPhrasePattern}}},
		{"再設定: 一致しない", ValidateResetPassword(validPhrase, "x"), fields{"confirmPassword": {msgNewPhraseMismatch}}},
		{"再設定: 確認が空白だけ", ValidateResetPassword(validPhrase, " "), fields{"confirmPassword": {msgNewPhraseMismatch, msgNewConfirmRequired}}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.want == nil {
				if tt.got != nil {
					t.Fatalf("誤りが無いはずが %+v", tt.got.Errors)
				}
				return
			}
			if tt.got == nil {
				t.Fatalf("誤りがあるはずが nil。期待: %v", tt.want)
			}
			if tt.got.Status != 400 || tt.got.Message != MessageInvalidInput {
				t.Errorf("状態と文言 = %d %q", tt.got.Status, tt.got.Message)
			}
			if !reflect.DeepEqual(map[string][]string(tt.got.Errors), tt.want) {
				t.Errorf("項目ごとの文言\n 得た: %v\n 期待: %v", tt.got.Errors, tt.want)
			}
		})
	}
}

// TestValidate_NotBlank は、空白だけかの判定が、unicode.IsSpace が空白とする字の一覧と同じかを、すべての字で確かめる。
// 字 r が一覧にあれば、r だけの値と r を2つ並べた値を空白だけとする。
func TestValidate_NotBlank(t *testing.T) {
	want := map[rune]bool{}
	for _, r := range []rune{0x20, 0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000} {
		want[r] = true
	}
	for _, span := range [][2]rune{{0x09, 0x0D}, {0x2000, 0x200A}} {
		for r := span[0]; r <= span[1]; r++ {
			want[r] = true
		}
	}
	for r := rune(0); r <= 0x10FFFF; r++ {
		if r >= 0xD800 && r <= 0xDFFF {
			continue
		}
		if got := notBlank(ch(r) + ch(r)); got == want[r] {
			t.Errorf("notBlank(U+%04X を2つ) = %v、空白の一覧にある = %v", r, got, want[r])
		}
	}
	if notBlank("") {
		t.Error(`notBlank("") = true`)
	}
}

// TestValidate_EmailFormat は、メールアドレスの形の判定を確かめる。
func TestValidate_EmailFormat(t *testing.T) {
	c63 := strings.Repeat("c", 63)
	tests := []struct {
		email string
		want  bool
	}{
		{"", true},
		{"user@example.com", true},
		{"noat", false},
		{"a@b@example.com", false},
		{"\"a@b\"@example.com", true},
		{"a..b@example.com", false},
		{strings.Repeat("a", 64) + "@example.com", true},
		{strings.Repeat("a", 65) + "@example.com", false},
		{"a@example.", false},
		{"a@example..com", false},
		{"a@b!c.com", true},
		{"a@例え。テスト", true},
		{"a@例え。", false},
		{"a@例え。。テスト", false},
		{"a@[127.0.0.1]", true},
		{"a@[IPv6:2001:db8::1]", true},
		{"a@ｘｎ--p1ai.com", true},
		{"a@xn--abc.com", false},
		{"a@xn--あ.com", false},
		{"a@" + ch(0x05D0) + "a" + ch(0x05D1) + ".com", false},
		{"a@" + ch(0x0627) + ch(0x0653) + ".com", true},
		{"a@a" + ch(0xFFFD) + "b.com", false},
		{"a@" + ch(0x1F600) + ".com", false},
		{"a@" + strings.Repeat("b", 63) + ".com", true},
		{"a@" + strings.Repeat("b", 64) + ".com", false},
		{"a@" + c63 + "." + c63 + "." + c63 + "." + strings.Repeat("d", 61), true},
		{"a@" + c63 + "." + c63 + "." + c63 + "." + strings.Repeat("d", 62), false},
	}
	for _, tt := range tests {
		if got := isEmailFormat(tt.email); got != tt.want {
			t.Errorf("isEmailFormat(%q) = %v, 期待 %v", tt.email, got, tt.want)
		}
	}
}
