package resume

import (
	"strings"
	"testing"
)

// sanitizeFileNameTests は、経歴書の名前と、sanitizeFileName が作るファイル名の表である。
// cb は、Java 版と答えが違う名前に付けた、変えた動きの一覧の番号である。Java 版の答えは、消す前の控えのファイル
// (testdata/export/filenames.json)と、Java 版の FileUtil.sanitizeFileName の規則から求めた。
var sanitizeFileNameTests = []struct {
	name, in, want, cb string
}{
	{name: "日本語と _ の名前", in: "職務経歴書_山田太郎", want: "職務経歴書_山田太郎"},
	{name: "絵文字を含む名前", in: "経歴書🎉✨", want: "経歴書🎉✨"},
	{name: "英字と数字と - の名前", in: "resume-2026", want: "resume-2026"},
	{name: "前後の半角の空白を除く", in: "  前後に空白  ", want: "前後に空白"},
	{name: "前後のタブと改行を除く", in: "\t タブと空白 \n", want: "タブと空白"},
	{name: "前後の全角の空白は残す", in: "　全角の空白　", want: "　全角の空白　"},
	{name: "前後の改行しない空白は残す", in: " 改行しない空白 ", want: " 改行しない空白 "},
	{name: "使えない9つの字を _ にする", in: `a/b\c:d*e?f"g<h>i|j`, want: "a_b_c_d_e_f_g_h_i_j"},
	{name: "制御の字を消す", in: "制御\u0001の\u001fとを含む", want: "制御のとを含む"},
	{name: "途中の改行と復帰を消す", in: "改行\nと\r復帰", want: "改行と復帰"},
	{name: "前後の制御の字を消す", in: "\u0001a\u007f", want: "a"},
	{name: "C1 の制御の字は残す", in: "a\u0080b", want: "a\u0080b"},
	{name: "_ だけの名前", in: "___", want: defaultFileName},
	{name: "使えない字だけの名前", in: "/:*", want: defaultFileName},
	{name: "制御の字だけの名前", in: "\u0001\u0002", want: defaultFileName},
	{name: "制御の字と _ だけの名前", in: "\u0001_", want: defaultFileName},
	{name: "制御の字と空白だけの名前", in: " \u0001 ", want: defaultFileName},
	{name: "空白だけの名前", in: "   ", want: defaultFileName},
	{name: "全角の空白だけの名前", in: "　", want: defaultFileName},
	{name: "空の名前", in: "", want: defaultFileName},
	{name: "前後の _ は残す", in: "_a_", want: "_a_"},
	{name: "_ の間に空白がある名前", in: "_ _", want: "_ _"},
	{name: "_ の間に行の区切りがある名前", in: "_ _", want: "_ _"},
	{name: ". で始まり . で終わる名前", in: ".dot.", want: ".dot."},
	// Java 版は、_ のあとに行の終わりの字が1つだけある名前を、_ だけの名前として扱っていた
	{name: "_ と最後の次の行の字", in: "__\u0085", want: "__\u0085", cb: "CB-112"},
	{name: "_ と最後の行の区切り", in: "__ ", want: "__ ", cb: "CB-112"},
	{name: "_ と最後の段落の区切り", in: "__ ", want: "__ ", cb: "CB-112"},
	// 255 字で切る。Java 版は UTF-16 の単位で数え、絵文字を2つと数えていた
	{name: "255 字の名前", in: strings.Repeat("あ", 255), want: strings.Repeat("あ", 255)},
	{name: "256 字の名前", in: strings.Repeat("a", 256), want: strings.Repeat("a", 255)},
	{name: "255 字目が絵文字の名前", in: strings.Repeat("a", 254) + "😀", want: strings.Repeat("a", 254) + "😀", cb: "CB-112"},
	{name: "絵文字の200字の名前", in: strings.Repeat("😀", 200), want: strings.Repeat("😀", 200), cb: "CB-112"},
	{name: "絵文字の256字の名前", in: strings.Repeat("😀", 256), want: strings.Repeat("😀", 255), cb: "CB-112"},
}

// TestSanitizeFileName は、経歴書の名前から、表のとおりのファイル名を作ることを確かめる。
func TestSanitizeFileName(t *testing.T) {
	for _, tt := range sanitizeFileNameTests {
		t.Run(tt.name, func(t *testing.T) {
			if got := sanitizeFileName(tt.in); got != tt.want {
				t.Errorf("sanitizeFileName(%q) = %q、want %q", tt.in, got, tt.want)
			}
		})
	}
}

// TestSanitizeFileName_DiffTableInChangedBehaviors は、Java 版と答えが違う名前の番号が、変えた動きの一覧にあることを確かめる。
func TestSanitizeFileName_DiffTableInChangedBehaviors(t *testing.T) {
	table := map[string]string{}
	for _, tt := range sanitizeFileNameTests {
		if tt.cb != "" {
			table[tt.in] = tt.cb
		}
	}
	checkDiffTableInChangedBehaviors(t, table)
}
