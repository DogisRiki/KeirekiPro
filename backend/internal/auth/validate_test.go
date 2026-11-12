package auth

import (
	"io/fs"
	"os"
	"reflect"
	"strconv"
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
	// emailOf は、長さが n の、形の正しいメールアドレスを返す。後ろの部分は63文字のラベルを「.」でつなぐ。
	emailOf := func(n int) string {
		domain := strings.Repeat("c", 63) + "." + strings.Repeat("c", 63) + "." + strings.Repeat("c", 63) + "."
		return "a@" + domain + strings.Repeat("d", n-2-len(domain))
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
		{"ログイン: 改行させない空白は空白でない", ValidateLogin(ch(0x00A0), ch(0x2007)+ch(0x202F)), nil},
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

// TestValidate_JavaWhitespace は、空白の判定が Java 21 の Character.isWhitespace と同じかを確かめる。
// 期待の一覧は、Java 21 で Character.isWhitespace が真になるすべてのコードポイントである。
func TestValidate_JavaWhitespace(t *testing.T) {
	want := map[rune]bool{}
	for _, r := range []rune{0x1680, 0x2028, 0x2029, 0x205F, 0x3000} {
		want[r] = true
	}
	for _, span := range [][2]rune{{0x09, 0x0D}, {0x1C, 0x20}, {0x2000, 0x2006}, {0x2008, 0x200A}} {
		for r := span[0]; r <= span[1]; r++ {
			want[r] = true
		}
	}
	for r := rune(0); r <= 0x10FFFF; r++ {
		if got := isJavaWhitespace(r); got != want[r] {
			t.Errorf("isJavaWhitespace(U+%04X) = %v", r, got)
		}
	}
}

// TestValidate_IDNAToASCII は、ドメインの部分の変換が、Java 版が使う JDK 21 の java.net.IDN.toASCII と同じ結果を
// 返すかを確かめる。メールアドレスの検査は変えたあとの長さだけを見るので、Punycode の符号そのものはこのテストで確かめる。
// testdata/nameprep/idna_vectors.txt の期待は、testdata/nameprep/Vectors.java で、Java の IDN.toASCII を動かして作った。
// 期待の「!」は、Java が IllegalArgumentException を投げたことを表す。
func TestValidate_IDNAToASCII(t *testing.T) {
	lines := readVectorLines(t, "idna_vectors.txt", 40)
	for _, line := range lines {
		quoted, want, ok := strings.Cut(line, "\t")
		if !ok {
			t.Fatalf("行の形が誤り: %q", line)
		}
		domain, err := strconv.Unquote(quoted)
		if err != nil {
			t.Fatalf("行 %q: %v", line, err)
		}
		got, ok := idnaToASCII(domain)
		if !ok {
			got = "!"
		}
		if got != want {
			t.Errorf("idnaToASCII(%s) = %q, Java 版は %q", quoted, got, want)
		}
	}
}

// readVectorLines は、testdata/nameprep の中のファイル name を行に分けて返す。行が minLines 行に満たなければテストを止める。
func readVectorLines(t *testing.T, name string, minLines int) []string {
	t.Helper()
	data, err := fs.ReadFile(os.DirFS("testdata/nameprep"), name)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	if len(lines) < minLines {
		t.Fatalf("%s の行が %d 行しかない", name, len(lines))
	}
	return lines
}

// TestValidate_EmailLikeHibernate は、メールアドレスの形の判定が、Java 版の Hibernate Validator 9.1.5 の
// EmailValidator と同じかを確かめる。testdata/nameprep/email_vectors.txt の期待は、testdata/nameprep/Vectors.java で、
// Java 版の判定を動かして作った。
func TestValidate_EmailLikeHibernate(t *testing.T) {
	named := []struct {
		email string
		want  bool
	}{
		{"", true},
		{"user@example.com", true},
		{"noat", false},
		{"a@b@example.com", false},
		{"\"a@b\"@example.com", true},
		{strings.Repeat("a", 64) + "@example.com", true},
		{strings.Repeat("a", 65) + "@example.com", false},
		{"a@example.", false},
		{"a@例え。", true},
		{"a@。", true},
		{"a@例え。。テスト", false},
		{"a@[127.0.0.1]", true},
		{"a@[IPv6:2001:db8::1]", true},
		{"a@ｘｎ--abc.com", true},
		{"a@xn--あ.com", false},
		{"a@" + ch(0x05D0) + "a" + ch(0x05D1) + ".com", false},
		{"a@" + ch(0x0627) + ch(0x0653) + ".com", true},
		{"a@a" + ch(0xFFFD) + "b.com", false},
		{"a@" + ch(0x1F600) + ".com", false},
		{"a@" + strings.Repeat("b", 63) + ".com", true},
		{"a@" + strings.Repeat("b", 64) + ".com", false},
	}
	for _, tt := range named {
		if got := isEmailLikeHibernate(tt.email); got != tt.want {
			t.Errorf("isEmailLikeHibernate(%q) = %v, 期待 %v", tt.email, got, tt.want)
		}
	}

	for _, line := range readVectorLines(t, "email_vectors.txt", 3800) {
		want, quoted, ok := strings.Cut(line, "\t")
		if !ok {
			t.Fatalf("行の形が誤り: %q", line)
		}
		email, err := strconv.Unquote(quoted)
		if err != nil {
			t.Fatalf("行 %q: %v", line, err)
		}
		if got := isEmailLikeHibernate(email); strconv.FormatBool(got) != want {
			t.Errorf("isEmailLikeHibernate(%s) = %v, Java 版は %s", quoted, got, want)
		}
	}
}
