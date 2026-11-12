package auth

import (
	"os"
	"slices"
	"strconv"
	"strings"
	"testing"
)

// TestRegister_CommonsEmailMatchesJava は、登録の受け付けのメールアドレスの確かめが、Java 版の Email.create が使う
// Apache Commons Validator 1.11.0 の EmailValidator.getInstance(false, false) と同じ判定を返すかを確かめる。
// testdata/commonsemail/vectors.txt の期待は、testdata/commonsemail/Gen.java で、Java 版の判定を動かして作った。
// このファイルの初めの説明のとおり、入力の検査を通らないメールアドレスは、呼ぶ側が先に断るので、比べない。
func TestRegister_CommonsEmailMatchesJava(t *testing.T) {
	data, err := os.ReadFile("testdata/commonsemail/vectors.txt")
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	if len(lines) < 6000 {
		t.Fatalf("vectors.txt の行が %d 行しかない", len(lines))
	}
	compared, accepted := 0, 0
	for i, line := range lines {
		want, quoted, ok := strings.Cut(line, "\t")
		if !ok {
			t.Fatalf("%d 行目の形が違う: %q", i+1, line)
		}
		email, err := strconv.Unquote(quoted)
		if err != nil {
			t.Fatalf("%d 行目の文字列を読めない: %v", i+1, err)
		}
		if !isEmailLikeHibernate(email) {
			continue
		}
		compared++
		got := commonsEmailValid(email)
		if got {
			accepted++
		}
		if strconv.FormatBool(got) != want {
			t.Errorf("%d 行目 commonsEmailValid(%q) = %v, want %s", i+1, email, got, want)
		}
	}
	// 比べた数が少なすぎると、確かめたことにならない
	if compared < 5000 || accepted < 4000 {
		t.Errorf("比べた数 = %d, 受け付けた数 = %d", compared, accepted)
	}
}

// TestRegister_CommonsEmailOutsideHibernate は、入力の検査を通らないメールアドレスのうち、基本多言語面の外の文字を
// 含まないものでも、Java 版と同じ判定を返すかを確かめる。呼ぶ側の順に頼らずに済む範囲を広く保つためである。
func TestRegister_CommonsEmailOutsideHibernate(t *testing.T) {
	data, err := os.ReadFile("testdata/commonsemail/vectors.txt")
	if err != nil {
		t.Fatal(err)
	}
	for i, line := range strings.Split(strings.TrimSuffix(string(data), "\n"), "\n") {
		want, quoted, _ := strings.Cut(line, "\t")
		email, err := strconv.Unquote(quoted)
		if err != nil {
			t.Fatalf("%d 行目の文字列を読めない: %v", i+1, err)
		}
		if isEmailLikeHibernate(email) || strings.ContainsFunc(email, func(r rune) bool { return r > 0xFFFF }) {
			continue
		}
		if got := commonsEmailValid(email); strconv.FormatBool(got) != want {
			t.Errorf("%d 行目 commonsEmailValid(%q) = %v, want %s", i+1, email, got, want)
		}
	}
}

// TestRegister_EmailCreateErrors は、Java 版の Email.create と同じく、空のメールアドレスと形の正しくないメールアドレスに
// 文言を返すかを確かめる。
func TestRegister_EmailCreateErrors(t *testing.T) {
	cases := []struct {
		email string
		want  []string
	}{
		{"user@example.com", nil},
		{"", []string{"メールアドレスが空です。"}},
		{" \t", []string{"メールアドレスが空です。"}},
		{"user@example.invalidtld", []string{"メールアドレスの形式が不正です。"}},
		{"user@localhost", []string{"メールアドレスの形式が不正です。"}},
	}
	for _, c := range cases {
		if got := emailCreateErrors(c.email); !slices.Equal(got, c.want) {
			t.Errorf("emailCreateErrors(%q) = %q, want %q", c.email, got, c.want)
		}
	}
}
