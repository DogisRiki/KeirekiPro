package auth

import (
	"slices"
	"testing"
)

// TestRegister_EmailErrors は、保存するメールアドレスの確かめが、空のメールアドレスと保存できない形のメールアドレスに
// 文言を返し、保存できるメールアドレスに文言を返さないかを確かめる。
func TestRegister_EmailErrors(t *testing.T) {
	blank := []string{"メールアドレスが空です。"}
	invalid := []string{"メールアドレスの形式が不正です。"}
	cases := []struct {
		email string
		want  []string
	}{
		{"user@example.com", nil},
		{"User.Name+tag@Sub.Example.CO.JP", nil},
		{"user@example.ck", nil},
		{"user@example.xn--p1ai", nil},
		{"user@例え.テスト.jp", nil},
		{"user@example.travelersinsurance", nil},
		{"\"a b\"@example.com", nil},
		{"user@[127.0.0.1]", nil},
		{"user@[IPv6:2001:db8::1]", nil},
		{"", blank},
		{" \t", blank},
		{"noat", invalid},
		{"a..b@example.com", invalid},
		{"user@example..com", invalid},
		{"user@example.com.", invalid},
		{"user@example.invalidtld", invalid},
		{"user@example.local", invalid},
		{"user@localhost", invalid},
		{"user@b!c.com", invalid},
		{"user@b_c.com", invalid},
		{"user@-example.com", invalid},
		{"user@ex" + ch(0x00AD) + "ample.com", invalid},
		{"user@ex" + ch(0x200B) + "ample.com", invalid},
		{"user@ex" + ch(0xFE0F) + "ample.com", invalid},
		{"user@[256.0.0.1]", invalid},
		{"user@[IPv6:127.0.0.1]", invalid},
		{"user@[2001:db8::1]", invalid},
	}
	for _, c := range cases {
		if got := emailErrors(c.email); !slices.Equal(got, c.want) {
			t.Errorf("emailErrors(%q) = %q, want %q", c.email, got, c.want)
		}
	}
}
