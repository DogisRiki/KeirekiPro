package users

import (
	"encoding/json"
	"io/fs"
	"os"
	"slices"
	"testing"
	"unicode/utf8"

	"github.com/google/uuid"
)

// usernameCase は、小タスク1.2 で Java 版に送った名前の要求と、Java 版の答えの1通りである。
type usernameCase struct {
	Name   string `json:"name"`
	Input  string `json:"input"`
	Answer struct {
		Status int    `json:"status"`
		Body   string `json:"body"`
	} `json:"answer"`
	StoredUsername *string `json:"storedUsername"`
}

// readUsernameCases は、testdata/username/cases.json の27通りを読む。
func readUsernameCases(t *testing.T) []usernameCase {
	t.Helper()
	b, err := fs.ReadFile(os.DirFS("testdata/username"), "cases.json")
	if err != nil {
		t.Fatalf("名前の見本を読めません: %v", err)
	}
	var file struct {
		Cases []usernameCase `json:"cases"`
	}
	if err := json.Unmarshal(b, &file); err != nil {
		t.Fatalf("名前の見本の JSON を読めません: %v", err)
	}
	if len(file.Cases) != 27 {
		t.Fatalf("名前の見本の数 = %d、期待 = 27", len(file.Cases))
	}
	return file.Cases
}

// javaStripRunes は、research.md の試作の記録の P6 に書いた、Java の String.strip() が名前の前後から取り除く字である。
var javaStripRunes = func() []rune {
	var rs []rune
	add := func(from, to rune) {
		for r := from; r <= to; r++ {
			rs = append(rs, r)
		}
	}
	add(0x0009, 0x000D)
	add(0x001C, 0x0020)
	add(0x1680, 0x1680)
	add(0x2000, 0x2006)
	add(0x2008, 0x200A)
	add(0x2028, 0x2029)
	add(0x205F, 0x205F)
	add(0x3000, 0x3000)
	return rs
}()

// javaKeptRunes は、P6 に書いた、空白に見えるが Java の String.strip() が取り除かない字である。
var javaKeptRunes = []rune{0x00A0, 0x2007, 0x202F, 0x0085, 0x200B}

func TestUpdateUserInfo_UsernameMatchesJava(t *testing.T) {
	for _, c := range readUsernameCases(t) {
		t.Run(c.Name, func(t *testing.T) {
			got, message := normalizeUsername(c.Input)
			switch c.Answer.Status {
			case 200:
				if message != "" || c.StoredUsername == nil || got != *c.StoredUsername {
					t.Errorf("名前 %+q の答え = %+q 文言 %q、Java 版の保存した名前 = %+q", c.Input, got, message, deref(c.StoredUsername))
				}
			case 400:
				var body struct {
					Errors map[string][]string `json:"errors"`
				}
				if err := json.Unmarshal([]byte(c.Answer.Body), &body); err != nil {
					t.Fatalf("Java 版の答えの本文を読めません: %v", err)
				}
				want := body.Errors["username"]
				if len(body.Errors) != 1 || len(want) != 1 {
					t.Fatalf("Java 版の答えの誤り = %v、期待 = 項目 username の文言1つ", body.Errors)
				}
				if message != want[0] {
					t.Errorf("名前 %+q の文言 = %q、Java 版の文言 = %q", c.Input, message, want[0])
				}
			case 500:
				// Java 版が 500 で答えた1通りは、NUL を含む名前である。名前の検査は通り、PostgreSQL が NUL を断った。
				// Go 版も名前の検査を通し、同じ名前をデータベースに渡す。この名前の前後には取り除く字が無い。
				if message != "" || got != c.Input {
					t.Errorf("名前 %+q の答え = %+q 文言 %q、期待 = 検査を通して同じ名前", c.Input, got, message)
				}
			default:
				t.Fatalf("Java 版の答えの状態の番号 = %d", c.Answer.Status)
			}
		})
	}

	// 前後の空白の判定を、P6 の一覧と、すべての字で比べる。字 r を名前の前と後ろに付け、取り除かれるかを見る。
	t.Run("前後から取り除く字", func(t *testing.T) {
		for r := rune(0); r <= utf8.MaxRune; r++ {
			if !utf8.ValidRune(r) {
				continue
			}
			got, message := normalizeUsername(string(r) + "a" + string(r))
			stripped := got == "a" && message == ""
			if want := slices.Contains(javaStripRunes, r); stripped != want {
				t.Errorf("字 U+%04X を取り除く = %v、P6 の一覧 = %v(答え %+q 文言 %q)", r, stripped, want, got, message)
			}
		}
		for _, r := range javaKeptRunes {
			if got, _ := normalizeUsername(string(r) + "a" + string(r)); got != string(r)+"a"+string(r) {
				t.Errorf("字 U+%04X の答え = %+q、期待 = 取り除かない", r, got)
			}
		}
	})
}

func TestUpdateUserInfo_ImageKey(t *testing.T) {
	id := uuid.MustParse("11111111-1111-4111-8111-000000000002")
	tests := []struct {
		ext  string
		want string
	}{
		{"png", "/profile/image/11111111-1111-4111-8111-000000000002.png"},
		{"jpeg", "/profile/image/11111111-1111-4111-8111-000000000002.jpeg"},
		// Java 版の ProfileImageKeys.fileName と同じく、拡張子が無ければ . も付けない。
		{"", "/profile/image/11111111-1111-4111-8111-000000000002"},
		// Java 版は String.isBlank で確かめるので、空白だけの拡張子も無いものとして扱う。
		{" \t", "/profile/image/11111111-1111-4111-8111-000000000002"},
	}
	for _, tt := range tests {
		if got := profileImageKey(id, tt.ext); got != tt.want {
			t.Errorf("profileImageKey(%q) = %q、期待 = %q", tt.ext, got, tt.want)
		}
	}
}

// deref は、nil のポインタを空の文字列として読む。
func deref(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}
