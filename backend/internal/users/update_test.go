package users

import (
	"slices"
	"strings"
	"testing"
	"unicode/utf8"

	"github.com/google/uuid"
)

// spaceRunes は、unicode.IsSpace が空白とし、名前の前後から取り除く字である。
var spaceRunes = func() []rune {
	var rs []rune
	add := func(from, to rune) {
		for r := from; r <= to; r++ {
			rs = append(rs, r)
		}
	}
	add(0x0009, 0x000D)
	add(0x0020, 0x0020)
	add(0x0085, 0x0085)
	add(0x00A0, 0x00A0)
	add(0x1680, 0x1680)
	add(0x2000, 0x200A)
	add(0x2028, 0x2029)
	add(0x202F, 0x202F)
	add(0x205F, 0x205F)
	add(0x3000, 0x3000)
	return rs
}()

// keptRunes は、空白に見えるか空白に近いが、unicode.IsSpace が空白としないので取り除かない字である。
var keptRunes = []rune{0x001C, 0x001F, 0x200B, 0x180E, 0xFEFF}

func TestNormalizeUsername(t *testing.T) {
	const (
		required = "ユーザー名は必ず指定してください。"
		tooLong  = "ユーザー名は50文字以内で入力してください。"
	)
	a50 := strings.Repeat("a", 50)
	hira50 := strings.Repeat("あ", 50)
	emoji25 := strings.Repeat("\U0001F600", 25)
	tests := []struct {
		name    string
		input   string
		want    string // 検査を通ったときに保存する名前
		message string // 検査で断るときの文言。通るときは空
	}{
		{"普通の名前", "山田太郎", "山田太郎", ""},
		{"空", "", "", required},
		{"半角の空白だけ", "   ", "", required},
		{"前後に半角の空白", "  山田  ", "山田", ""},
		{"前にタブ、後ろに改行", "\t山田\n", "山田", ""},
		{"前後に全角の空白", "\u3000山田\u3000", "山田", ""},
		{"全角の空白だけ", "\u3000", "", required},
		// 改行しない空白と次の行の字は取り除き、情報の区切りの制御文字は残す(変えた動きの一覧の CB-113)。
		{"前後にノーブレークスペース", "\u00a0山田\u00a0", "山田", ""},
		{"前に数字幅の空白", "\u2007山田", "山田", ""},
		{"前にゼロ幅の空白", "\u200b山田", "\u200b山田", ""},
		{"前に NEL", "\u0085山田", "山田", ""},
		{"ノーブレークスペースだけ", "\u00a0", "", required},
		{"前後に行と段落の区切り", "\u2028山田\u2029", "山田", ""},
		{"前後に情報の区切りの制御文字", "\u001c山田\u001f", "\u001c山田\u001f", ""},
		{"前後に数式の空白とオガムの空白", "\u205f山田\u1680", "山田", ""},
		{"前にモンゴル語の母音の区切り", "\u180e山田", "\u180e山田", ""},
		{"前に BOM", "\ufeff山田", "\ufeff山田", ""},
		{"間に空白", "山田 太郎", "山田 太郎", ""},
		{"ASCII の50文字", a50, a50, ""},
		{"ASCII の51文字", a50 + "a", "", tooLong},
		{"ひらがなの50文字", hira50, hira50, ""},
		{"ひらがなの51文字", hira50 + "あ", "", tooLong},
		// 長さは UTF-16 の単位で数えるので、絵文字は1字で2つに数える。
		{"絵文字の25字", emoji25, emoji25, ""},
		{"絵文字の25字と1文字", emoji25 + "a", "", tooLong},
		{"前後の空白を除くと50文字", "  " + a50 + "  ", a50, ""},
		// NUL を含む名前は、名前の検査を通す。保存するときに PostgreSQL が断る。
		{"NUL を含む", "a\x00b", "a\x00b", ""},
		{"山かっこを含む", "<script>", "<script>", ""},
		{"全角の英字", "Ｔｅｓｔ", "Ｔｅｓｔ", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, message := normalizeUsername(tt.input)
			if message != tt.message {
				t.Errorf("名前 %+q の文言 = %q、期待 = %q", tt.input, message, tt.message)
			}
			if tt.message == "" && got != tt.want {
				t.Errorf("名前 %+q の答え = %+q、期待 = %+q", tt.input, got, tt.want)
			}
		})
	}

	// 前後の空白の判定を、spaceRunes の一覧と、すべての字で比べる。字 r を名前の前と後ろに付け、取り除かれるかを見る。
	t.Run("前後から取り除く字", func(t *testing.T) {
		for r := rune(0); r <= utf8.MaxRune; r++ {
			if !utf8.ValidRune(r) {
				continue
			}
			got, message := normalizeUsername(string(r) + "a" + string(r))
			stripped := got == "a" && message == ""
			if want := slices.Contains(spaceRunes, r); stripped != want {
				t.Errorf("字 U+%04X を取り除く = %v、空白の一覧 = %v(答え %+q 文言 %q)", r, stripped, want, got, message)
			}
		}
		for _, r := range keptRunes {
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
