package httpapi

import (
	"encoding/json"
	"os"
	"testing"
)

// TestFormatContentDisposition_MatchesJava は、小タスク1.2 で控えた exportdisposition.json のすべての項目で、項目のファイル名と
// 出し方から、Java 版と同じ Content-Disposition のヘッダを作ることを確かめる(要件2の受入基準3)。
func TestFormatContentDisposition_MatchesJava(t *testing.T) {
	b, err := os.ReadFile("testdata/exportdisposition.json")
	if err != nil {
		t.Fatal(err)
	}
	var entries []struct {
		Disposition string `json:"disposition"`
		FileName    string `json:"fileName"`
		Header      string `json:"header"`
	}
	if err := json.Unmarshal(b, &entries); err != nil {
		t.Fatal(err)
	}
	if len(entries) == 0 {
		t.Fatal("正解のファイルに項目が無い")
	}
	for _, e := range entries {
		if e.Disposition != "inline" && e.Disposition != "attachment" {
			t.Fatalf("出し方 %q を読めない", e.Disposition)
		}
		if got := formatContentDisposition(e.Disposition == "inline", e.FileName); got != e.Header {
			t.Errorf("ファイル名 %q と出し方 %s のヘッダが\n%s\n、Java 版は\n%s", e.FileName, e.Disposition, got, e.Header)
		}
	}
}

// TestFormatContentDisposition_EscapesQuoteAndBackslash は、ファイル名の " と \ を、filename="…" では前に \ を置いて書き、
// filename*= では %22 と %5C に書くことを確かめる(要件2の受入基準3)。sanitizeFileName が " と \ を _ に替えるので、
// 正解のファイルのファイル名には " と \ が入らない。期待する値は、Spring 7.0.10 の ContentDisposition の
// appendName と encodeRfc5987Filename から求め、JDK 21 で Spring 7.0.10 を動かして同じ字になることを確かめた。
func TestFormatContentDisposition_EscapesQuoteAndBackslash(t *testing.T) {
	cases := []struct {
		name     string
		inline   bool
		fileName string
		want     string
	}{
		{name: "ASCII の名前", fileName: `a"b\c.md`, want: `attachment; filename="a\"b\\c.md"; filename*=UTF-8''a%22b%5Cc.md`},
		{name: "ASCII でない字の後ろ", inline: true, fileName: `é"\.pdf`, want: `inline; filename="e\"\\.pdf"; filename*=UTF-8''%C3%A9%22%5C.pdf`},
		{name: "続く記号", fileName: `""\\`, want: `attachment; filename="\"\"\\\\"; filename*=UTF-8''%22%22%5C%5C`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := formatContentDisposition(c.inline, c.fileName); got != c.want {
				t.Errorf("ヘッダが\n%s\n、期待は\n%s", got, c.want)
			}
		})
	}
}

// TestFormatContentDisposition_JavaRules は、正解のファイルに無い Spring 7.0.10 の ContentDisposition の規則を確かめる
// (要件2の受入基準3)。期待する値は、Spring の appendName と transliterateToAscii と encodeRfc5987Filename と、
// Java の UTF-8 への書き方から求め、JDK 21 で Spring 7.0.10 を動かして同じ字になることを確かめた。
func TestFormatContentDisposition_JavaRules(t *testing.T) {
	cases := []struct {
		name     string
		fileName string
		want     string
	}{
		// 制御の字は filename="…" からだけ落とし、filename*= には %XX で書く
		{name: "制御の字", fileName: "a\x01b\x7fc", want: `attachment; filename="abc"; filename*=UTF-8''a%01b%7Fc`},
		// 255 で割れた絵文字の前の半分は、filename="…" では _ 1つに、filename*= では Java の UTF-8 への書き方と同じく ? に書く
		{name: "割れた絵文字の前の半分", fileName: "a\xed\xa0\xbd.md", want: `attachment; filename="a_.md"; filename*=UTF-8''a%3F.md`},
		// ハングルは正準分解で3つの字母に分かれ、どれも結合の記号ではないので _ を3つ書く
		{name: "ハングル", fileName: "한", want: `attachment; filename="___"; filename*=UTF-8''%ED%95%9C`},
		// 結合の記号は、間隔をとるもの(Mc)と囲むもの(Me)も書かない
		{name: "結合の記号", fileName: "aாb⃝c", want: `attachment; filename="abc"; filename*=UTF-8''a%E0%AE%BEb%E2%83%9Dc`},
		// 互換分解だけを持つ字は、正準分解では分かれないので _ にする
		{name: "互換分解だけを持つ字", fileName: "①ﬁ", want: `attachment; filename="__"; filename*=UTF-8''%E2%91%A0%EF%AC%81`},
		// U+0897 は Unicode 16.0 で足した結合の記号で、JDK 21 の Unicode 15.0 では割り当てられていないので _ にする
		{name: "Unicode 15.0 に無い字", fileName: "aࢗb", want: `attachment; filename="a_b"; filename*=UTF-8''a%E0%A2%97b`},
		// 決まった字の表の字
		{name: "字の表", fileName: "äöüÄÖÜßæÆœŒ", want: `attachment; filename="aeoeueAeOeUessaeAEoeOE"; filename*=UTF-8''%C3%A4%C3%B6%C3%BC%C3%84%C3%96%C3%9C%C3%9F%C3%A6%C3%86%C5%93%C5%92`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := formatContentDisposition(false, c.fileName); got != c.want {
				t.Errorf("ヘッダが\n%s\n、期待は\n%s", got, c.want)
			}
		})
	}
}
