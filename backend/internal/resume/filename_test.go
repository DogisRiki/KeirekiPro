package resume

import (
	"encoding/json"
	"os"
	"strings"
	"testing"
)

// javaUTF8 は、Java の文字列を UTF-8 に書くときと同じく、s の中の対にならないサロゲートを「?」にする。
// sanitizeFileName は、UTF-16 の255で切って半分に割れた字を、Java 版の文字列と同じくサロゲートのまま返す。
// Java 版のヘッダの filename*= は、その字を UTF-8 に書くときに「?」に替えたものである。
func javaUTF8(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == 0xED && i+2 < len(s) && s[i+1] >= 0xA0 && s[i+1] <= 0xBF {
			b.WriteByte('?')
			i += 2
			continue
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

// TestSanitizeFileName_MatchesJava は、小タスク1.2 で控えた filenames.json のすべての名前で、Java 版と同じファイル名に
// なることを確かめる(要件2の受入基準3)。空白だけの名前と空の名前は、Java 版が出力の前提の検査で断るので、
// status が 200 の項目だけをファイル名で比べる。
func TestSanitizeFileName_MatchesJava(t *testing.T) {
	b, err := os.ReadFile("testdata/export/filenames.json")
	if err != nil {
		t.Fatal(err)
	}
	var entries []struct {
		ResumeName string `json:"resumeName"`
		Status     int    `json:"status"`
		FileName   string `json:"fileName"`
	}
	if err := json.Unmarshal(b, &entries); err != nil {
		t.Fatal(err)
	}
	compared := 0
	for _, e := range entries {
		if e.Status != 200 {
			continue
		}
		compared++
		if got := javaUTF8(sanitizeFileName(e.ResumeName)) + ".md"; got != e.FileName {
			t.Errorf("名前 %q のファイル名が %q、Java 版は %q", e.ResumeName, got, e.FileName)
		}
	}
	if compared == 0 {
		t.Fatal("比べた項目が無い")
	}
}

// TestSanitizeFileName_JavaRules は、正解のファイルに無い Java 版の規則を確かめる(要件2の受入基準3)。
// 期待する値は、Java 版の FileUtil.sanitizeFileName と java.util.regex の規則から求めた。
func TestSanitizeFileName_JavaRules(t *testing.T) {
	cases := []struct {
		name, in, want string
	}{
		// 正規表現の $ は、最後の行の終わりの字の前にも当たる。制御の字ではない U+0085、U+2028、U+2029 が、その字にあたる
		{name: "_ だけと最後の段落の区切り", in: "__ ", want: "resume"},
		{name: "_ だけと最後の行の区切り", in: "__ ", want: "resume"},
		{name: "_ だけと最後の次の行の字", in: "__\u0085", want: "\u0085"},
		{name: "行の区切りが途中にある", in: "_ _", want: "_ _"},
		// trim は U+0020 以下の字だけを除き、\p{Cntrl} は ASCII の制御の字だけを消す
		{name: "C1 の制御の字は残る", in: "a\u0080b", want: "a\u0080b"},
		{name: "前後の制御の字は除く", in: "\u0001a\u007f", want: "a"},
		// 255 で切ったとき、割れた絵文字の前の半分はサロゲートのまま残る
		{name: "255 で割れた絵文字", in: strings.Repeat("a", 254) + "😀", want: strings.Repeat("a", 254) + "\xed\xa0\xbd"},
		{name: "255 でちょうど終わる絵文字", in: strings.Repeat("a", 253) + "😀b", want: strings.Repeat("a", 253) + "😀"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := sanitizeFileName(c.in); got != c.want {
				t.Errorf("ファイル名が %q、期待は %q", got, c.want)
			}
		})
	}
}
