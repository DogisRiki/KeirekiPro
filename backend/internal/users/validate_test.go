package users

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// validPhrase は、パスワードの検査をすべて通る値である。
const validPhrase = "Abcdefg1"

type fieldMessages = map[string][]string

// validateCase は、検査の関数の結果 got と、項目ごとの文言の期待 want の組である。want が nil なら誤りが無いことを期待する。
type validateCase struct {
	name string
	got  *auth.Error
	want fieldMessages
}

// checkValidateCases は、それぞれの組の結果が期待と同じかを確かめる。1つの項目の文言は、並ぶ順まで比べる。
func checkValidateCases(t *testing.T, tests []validateCase) {
	t.Helper()
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
			if tt.got.Status != 400 || tt.got.Message != auth.MessageInvalidInput {
				t.Errorf("状態と文言 = %d %q", tt.got.Status, tt.got.Message)
			}
			if !reflect.DeepEqual(map[string][]string(tt.got.Errors), tt.want) {
				t.Errorf("項目ごとの文言\n 得た: %v\n 期待: %v", tt.got.Errors, tt.want)
			}
		})
	}
}

// emailOf は、長さが n の、形の正しいメールアドレスを返す。後ろの部分は63文字のラベルを「.」でつなぐ。
func emailOf(n int) string {
	domain := strings.Repeat("c", 63) + "." + strings.Repeat("c", 63) + "." + strings.Repeat("c", 63) + "."
	return "a@" + domain + strings.Repeat("d", n-2-len(domain))
}

// ptr は、s を指すポインタを返す。
func ptr(s string) *string {
	return &s
}

func TestValidate_ChangePasswordBoundaries(t *testing.T) {
	checkValidateCases(t, []validateCase{
		{"正しい値", ValidateChangePassword("x", validPhrase), nil},
		{"空", ValidateChangePassword("", ""), fieldMessages{
			"nowPassword": {MessageNowPhraseRequired},
			"newPassword": {MessageNewPhraseRequired, MessageNewPhraseLength, MessageNewPhrasePattern},
		}},
		{"空白だけ", ValidateChangePassword(" \t", "        "), fieldMessages{
			"nowPassword": {MessageNowPhraseRequired},
			"newPassword": {MessageNewPhraseRequired, MessageNewPhrasePattern},
		}},
		{"全角の空白だけ", ValidateChangePassword("　", validPhrase), fieldMessages{"nowPassword": {MessageNowPhraseRequired}}},
		{"現在のパスワードは長さと形を検査しない", ValidateChangePassword("a", validPhrase), nil},
		{"7文字", ValidateChangePassword("x", "Abcdef1"), fieldMessages{"newPassword": {MessageNewPhraseLength}}},
		{"8文字", ValidateChangePassword("x", "Abcdef12"), nil},
		{"72バイト", ValidateChangePassword("x", "Ab1"+strings.Repeat("a", 69)), nil},
		{"73バイト", ValidateChangePassword("x", "Ab1"+strings.Repeat("a", 70)), fieldMessages{"newPassword": {MessageNewPhraseLength}}},
		{"全角で72バイト", ValidateChangePassword("x", "Ab1"+strings.Repeat("あ", 23)), nil},
		{"全角で73バイト", ValidateChangePassword("x", "Ab1a"+strings.Repeat("あ", 23)), fieldMessages{"newPassword": {MessageNewPhraseLength}}},
		{"数字が無い", ValidateChangePassword("x", "Abcdefgh"), fieldMessages{"newPassword": {MessageNewPhrasePattern}}},
		{"英大文字が無い", ValidateChangePassword("x", "abcdefg1"), fieldMessages{"newPassword": {MessageNewPhrasePattern}}},
		{"英小文字が無い", ValidateChangePassword("x", "ABCDEFG1"), fieldMessages{"newPassword": {MessageNewPhrasePattern}}},
		{"改行を含む", ValidateChangePassword("x", validPhrase+"\n"), fieldMessages{"newPassword": {MessageNewPhrasePattern}}},
	})
}

func TestValidate_SetEmailAndPasswordBoundaries(t *testing.T) {
	checkValidateCases(t, []validateCase{
		{"正しい値", ValidateSetEmailAndPassword(ptr("user@example.com"), validPhrase, ptr(validPhrase)), nil},
		{"メールアドレスが null", ValidateSetEmailAndPassword(nil, validPhrase, ptr(validPhrase)), nil},
		{"メールアドレスが空の文字列", ValidateSetEmailAndPassword(ptr(""), validPhrase, ptr(validPhrase)), nil},
		{"メールアドレスが255文字", ValidateSetEmailAndPassword(ptr(emailOf(255)), validPhrase, ptr(validPhrase)), nil},
		{"メールアドレスが256文字", ValidateSetEmailAndPassword(ptr(emailOf(256)), validPhrase, ptr(validPhrase)), fieldMessages{"email": {MessageEmailTooLong}}},
		{"メールアドレスの形でない", ValidateSetEmailAndPassword(ptr("bad"), validPhrase, ptr(validPhrase)), fieldMessages{"email": {MessageEmailInvalid}}},
		{"メールアドレスが256文字で形でない", ValidateSetEmailAndPassword(ptr(strings.Repeat("b", 256)), validPhrase, ptr(validPhrase)), fieldMessages{"email": {MessageEmailTooLong, MessageEmailInvalid}}},
		{"パスワードが空", ValidateSetEmailAndPassword(nil, "", ptr("")), fieldMessages{
			"password": {MessagePhraseRequired, MessagePhraseLength, MessagePhrasePattern},
		}},
		{"パスワードが空白だけ", ValidateSetEmailAndPassword(nil, "        ", ptr("        ")), fieldMessages{
			"password": {MessagePhraseRequired, MessagePhrasePattern},
		}},
		{"パスワードが7文字", ValidateSetEmailAndPassword(nil, "Abcdef1", ptr("Abcdef1")), fieldMessages{"password": {MessagePhraseLength}}},
		{"パスワードが8文字", ValidateSetEmailAndPassword(nil, "Abcdef12", ptr("Abcdef12")), nil},
		{"パスワードが72バイト", ValidateSetEmailAndPassword(nil, "Ab1"+strings.Repeat("a", 69), ptr("Ab1"+strings.Repeat("a", 69))), nil},
		{"パスワードが73バイト", ValidateSetEmailAndPassword(nil, "Ab1"+strings.Repeat("a", 70), ptr("Ab1"+strings.Repeat("a", 70))), fieldMessages{"password": {MessagePhraseLength}}},
		{"パスワードが全角で72バイト", ValidateSetEmailAndPassword(nil, "Ab1"+strings.Repeat("あ", 23), ptr("Ab1"+strings.Repeat("あ", 23))), nil},
		{"パスワードが全角で73バイト", ValidateSetEmailAndPassword(nil, "Ab1a"+strings.Repeat("あ", 23), ptr("Ab1a"+strings.Repeat("あ", 23))), fieldMessages{"password": {MessagePhraseLength}}},
		{"パスワードに数字が無い", ValidateSetEmailAndPassword(nil, "Abcdefgh", ptr("Abcdefgh")), fieldMessages{"password": {MessagePhrasePattern}}},
		{"確認が一致しない", ValidateSetEmailAndPassword(nil, validPhrase, ptr(validPhrase+"x")), fieldMessages{"confirmPassword": {MessagePhraseMismatch}}},
		{"確認が空の文字列", ValidateSetEmailAndPassword(nil, validPhrase, ptr("")), fieldMessages{"confirmPassword": {MessagePhraseMismatch}}},
		{"確認が null", ValidateSetEmailAndPassword(nil, validPhrase, nil), nil},
		{"すべての項目が誤り", ValidateSetEmailAndPassword(ptr("bad"), "a", ptr("b")), fieldMessages{
			"email":           {MessageEmailInvalid},
			"password":        {MessagePhraseLength, MessagePhrasePattern},
			"confirmPassword": {MessagePhraseMismatch},
		}},
	})
}

// changePasswordBody と setEmailAndPasswordBody は、生成した要求の型(internal/httpapi/gen の ChangePasswordRequest と
// SetEmailAndPasswordRequest)と同じ項目の型と JSON の名前を持つ。機能のパッケージは internal/httpapi を読めないので、ここに写す。
// 項目を省いた本文を読むと、文字列の項目は空の文字列に、ポインタの項目は nil になる。
type changePasswordBody struct {
	NewPassword string `json:"newPassword"`
	NowPassword string `json:"nowPassword"`
}

type setEmailAndPasswordBody struct {
	ConfirmPassword *string `json:"confirmPassword,omitempty"`
	Email           *string `json:"email,omitempty"`
	Password        string  `json:"password"`
}

func TestValidate_MissingFields(t *testing.T) {
	decode := func(t *testing.T, body string, v any) {
		t.Helper()
		if err := json.Unmarshal([]byte(body), v); err != nil {
			t.Fatalf("本文 %s を読めない: %v", body, err)
		}
	}

	var change changePasswordBody
	decode(t, `{}`, &change)
	var changeNow changePasswordBody
	decode(t, `{"newPassword":"`+validPhrase+`"}`, &changeNow)
	var changeNew changePasswordBody
	decode(t, `{"nowPassword":"x"}`, &changeNew)

	var set setEmailAndPasswordBody
	decode(t, `{}`, &set)
	var setNoConfirm setEmailAndPasswordBody
	decode(t, `{"email":"user@example.com","password":"`+validPhrase+`"}`, &setNoConfirm)

	checkValidateCases(t, []validateCase{
		{"パスワードの変更: 2つとも省く", ValidateChangePassword(change.NowPassword, change.NewPassword), fieldMessages{
			"nowPassword": {MessageNowPhraseRequired},
			"newPassword": {MessageNewPhraseRequired, MessageNewPhraseLength, MessageNewPhrasePattern},
		}},
		{"パスワードの変更: 2つとも空の文字列", ValidateChangePassword("", ""), fieldMessages{
			"nowPassword": {MessageNowPhraseRequired},
			"newPassword": {MessageNewPhraseRequired, MessageNewPhraseLength, MessageNewPhrasePattern},
		}},
		{"パスワードの変更: nowPassword を省く", ValidateChangePassword(changeNow.NowPassword, changeNow.NewPassword), fieldMessages{
			"nowPassword": {MessageNowPhraseRequired},
		}},
		{"パスワードの変更: newPassword を省く", ValidateChangePassword(changeNew.NowPassword, changeNew.NewPassword), fieldMessages{
			"newPassword": {MessageNewPhraseRequired, MessageNewPhraseLength, MessageNewPhrasePattern},
		}},
		{"設定: すべて省く", ValidateSetEmailAndPassword(set.Email, set.Password, set.ConfirmPassword), fieldMessages{
			"password": {MessagePhraseRequired, MessagePhraseLength, MessagePhrasePattern},
		}},
		{"設定: password を空の文字列にし、ほかを省く", ValidateSetEmailAndPassword(nil, "", nil), fieldMessages{
			"password": {MessagePhraseRequired, MessagePhraseLength, MessagePhrasePattern},
		}},
		{"設定: confirmPassword を省く", ValidateSetEmailAndPassword(setNoConfirm.Email, setNoConfirm.Password, setNoConfirm.ConfirmPassword), nil},
	})
	if set.Email != nil || set.ConfirmPassword != nil || set.Password != "" {
		t.Errorf("省いた本文の読み方 = %+v、期待 = ポインタは nil、文字列は空", set)
	}
}
