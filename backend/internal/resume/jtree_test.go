package resume

import (
	"slices"
	"strconv"
	"strings"
	"testing"
)

// dumpJV は、値の木 v を、種類が分かる字にする。オブジェクトの欄は名前の順に並べ、同じ名前の欄はあとの値だけを書く。
func dumpJV(v *jv) string {
	switch v.kind {
	case jvNull:
		return "null"
	case jvBool:
		return strconv.FormatBool(v.truth)
	case jvNumber:
		return "n:" + v.text
	case jvString:
		return strconv.Quote(v.text)
	case jvArray:
		parts := make([]string, len(v.items))
		for i, item := range v.items {
			parts[i] = dumpJV(item)
		}
		return "[" + strings.Join(parts, ",") + "]"
	default:
		last := map[string]*jv{}
		names := make([]string, 0, len(v.members))
		for _, m := range v.members {
			if _, seen := last[m.name]; !seen {
				names = append(names, m.name)
			}
			last[m.name] = m.value
		}
		slices.Sort(names)
		parts := make([]string, len(names))
		for i, name := range names {
			parts[i] = strconv.Quote(name) + ":" + dumpJV(last[name])
		}
		return "{" + strings.Join(parts, ",") + "}"
	}
}

// mustParseJTree は、in を parseJTree で読み、読めなければテストを止める。
func mustParseJTree(t *testing.T, in string) *jv {
	t.Helper()
	v, ok := parseJTree([]byte(in))
	if !ok {
		t.Fatalf("parseJTree(%q) を読めません", in)
	}
	return v
}

// TestParseJTree_LoneSurrogate は、parseJTree が、文字列を Java の文字列と同じ UTF-16 の単位の並びとして読み、
// \uD800 から \uDFFF の番号の対になっていないサロゲートを WTF-8 のバイトで残すことを確かめる(要件2の受入基準1)。
// 「Java 版の答え」の場合は、Java 版に戻した本文の字と、Java 版が答えに書いた字(testdata/backup/restore.json)である。
// 木の字を JavaJSON で書くと、Java 版が答えに書いた字に戻る。
func TestParseJTree_LoneSurrogate(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
		java string
	}{
		{"前の半分", `"x\uD800y"`, "x\xed\xa0\x80y", `"x\uD800y"`},
		{"後ろの半分", `"\uDFFF"`, "\xed\xbf\xbf", `"\uDFFF"`},
		{"小文字の16進数", `"\udbff"`, "\xed\xaf\xbf", `"\uDBFF"`},
		{"前の半分が2つ続く", `"\uDBFF\uD800"`, "\xed\xaf\xbf\xed\xa0\x80", `"\uDBFF\uD800"`},
		{"後ろの半分のあとの前の半分", `"\uDC00\uD800"`, "\xed\xb0\x80\xed\xa0\x80", `"\uDC00\uD800"`},
		{"番号で書いた組は1つの字になる", `"\uD83D\uDE00"`, "\U0001F600", `"\uD83D\uDE00"`},
		{"番号の前の半分と UTF-8 の字", "\"\\uD83D\U0001F600\"", "\xed\xa0\xbd\U0001F600", `"\uD83D\uD83D\uDE00"`},
		{"ほかの番号", `"\u0041\u00e9\u3042\"\\\/\b\f\n\r\t"`, "Aéあ\"\\/\b\f\n\r\t", `"Aéあ\"\\/\b\f\n\r\t"`},
		{"UTF-8 の字", "\"経歴書\U00020BB7\u007f\"", "経歴書\U00020BB7\u007f", "\"経歴書\\uD842\\uDFB7\u007f\""},
		// Jackson は、短く書けるのに長く書いた字を読めない字としない(UTF8StreamJsonParser の _decodeUtf8_2 と _decodeUtf8_4)
		{"長く書いた2バイトの字", "\"a\xc1\x81\"", "aA", `"aA"`},
		{"U+10FFFF を超える4バイトの字", "\"\xf5\x80\x80\x80\"", "\xed\xb3\x80\xed\xb0\x80", `"\uDCC0\uDC00"`},
		{"Java 版の答えの前の半分", `"強み\uD800の中身"`, "強み\xed\xa0\x80の中身", `"強み\uD800の中身"`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			v := mustParseJTree(t, c.in)
			if v.kind != jvString || v.text != c.want {
				t.Fatalf("parseJTree(%q) = %s, want %q", c.in, dumpJV(v), c.want)
			}
			if got := string(JavaJSON(v.text)); got != c.java {
				t.Errorf("JavaJSON = %s, want %s", got, c.java)
			}
		})
	}

	// 欄の名前では、Java 版の Jackson(jackson-core 3.1.7 の UTF8StreamJsonParser の parseEscapedName と、
	// JsonParserBase の _decodeSurrogate と _reportUnexpectedLowSurrogate)は、番号で書いた前の半分のサロゲートのすぐあとに、
	// 後ろの半分のサロゲートの番号が続かない名前と、番号で書いた後ろの半分のサロゲートだけの名前を読めない。
	// UTF-8 のバイトで書いた字と、文字列の値は、この規則を受けない。
	t.Run("欄の名前の対になっていないサロゲート", func(t *testing.T) {
		for _, in := range []string{
			`{"a\uD800":1}`,
			`{"\uDC00":1}`,
			`{"\uD800x":1}`,
			`{"\uD800\n":1}`,
			`{"\uD800\uD800":1}`,
			`{"\uD800\u0041":1}`,
			`{"\uD800\q":1}`,
			`{"\uD800`,
			`{"\uD800\`,
		} {
			if v, ok := parseJTree([]byte(in)); ok {
				t.Errorf("parseJTree(%q) = %s, want 読めない", in, dumpJV(v))
			}
		}
	})
	t.Run("欄の名前のサロゲートの組", func(t *testing.T) {
		for in, want := range map[string]string{
			`{"\uD83D\uDE00":1}`:       "{\"\U0001F600\":n:1}",
			`{"a\udbff\udfffb":1}`:     `{"a\U0010ffffb":n:1}`,
			`{"a":"\uD800"}`:           `{"a":"\xed\xa0\x80"}`,
			"{\"\xf5\x80\x80\x80\":1}": `{"\xed\xb3\x80\xed\xb0\x80":n:1}`,
			`{"b":"\uDC00x"}`:          `{"b":"\xed\xb0\x80x"}`,
		} {
			if got := dumpJV(mustParseJTree(t, in)); got != want {
				t.Errorf("parseJTree(%q) = %s, want %s", in, got, want)
			}
		}
	})
}

// TestParseJTree_Malformed は、parseJTree が、Java 版の Jackson が読めない本文を読めない本文とし、
// Jackson が読む本文を読むことを確かめる(要件4の受入基準6)。「Java 版」と書いた場合は、Java 版に送って、
// 400 と「入力エラーがあります。」で答えた本文と、BOM を付けて 201 で戻した本文である(research.md の試作の記録)。
// ほかの場合は、Jackson(jackson-core 3.1.7)の既定の読み方(JSON の規則にない書き方を読めない。入れ子の深さの上限は 500、
// 欄の名前の長さの上限は 50,000 バイト)である。
func TestParseJTree_Malformed(t *testing.T) {
	nest := func(n int) string {
		return `{"a":` + strings.Repeat("[", n-1) + strings.Repeat("]", n-1) + `}`
	}
	name := func(s string) string {
		return `{"` + s + `":1}`
	}
	cases := []struct {
		name string
		in   string
		ok   bool
	}{
		{"Java 版 空", "", false},
		{"Java 版 { だけ", "{", false},
		{"Java 版 JSON でない語", "xyz", false},
		{"Java 版 途中で切れた本文", `{"version":"1.0","resume":{"name":"経歴`, false},
		{"Java 版 引用符が '", `{'version':'1.0'}`, false},
		{"Java 版 UTF-8 として読めない字", "{\"a\":\"\xff\"}", false},
		{"Java 版 頭の BOM", "\xef\xbb\xbf{\"a\":1}", true},
		{"空白だけ", " \t\r\n", false},
		{"空白でない制御の字", "\x00{}", false},
		{"改ページは空白でない", "\f{}", false},
		{"2つ目の BOM", "\xef\xbb\xbf\xef\xbb\xbf{}", false},
		{"欄の名前を囲まない", `{a:1}`, false},
		{"欄の名前が数", `{1:1}`, false},
		{": が無い", `{"a" 1}`, false},
		{"値が無い", `{"a":}`, false},
		{"オブジェクトの最後の ,", `{"a":1,}`, false},
		{"並びの最後の ,", `[1,]`, false},
		{"並びの先頭の ,", `[,1]`, false},
		{"区切りの無い値", `[1 2]`, false},
		{"閉じない並び", `[1`, false},
		{"閉じない欄", `{"a":1`, false},
		{"閉じない名前", `{"a`, false},
		{"閉じない文字列", `"abc`, false},
		{"番号にしない改行", "\"a\nb\"", false},
		{"番号にしない 0x1F", "\"a\x1fb\"", false},
		{"知らない番号", `"\q"`, false},
		{"番号の ' ", `"\'"`, false},
		{"短い \\u", `"\u12"`, false},
		{"16進数でない \\u", `"\u12G4"`, false},
		{"本文の終わりの \\", `"\`, false},
		{"サロゲートの UTF-8 のバイト", "\"\xed\xa0\x80\"", false},
		{"続きのバイトの無い字", "\"\xe3\x81\"", false},
		{"続きのバイトが誤った字", "\"\xe3\x41\x81\"", false},
		{"続きのバイトから始まる字", "\"\x80\"", false},
		{"5バイトの字の頭", "\"\xf8\x80\x80\x80\x80\"", false},
		{"先頭の 0 を続けた数", `[01]`, false},
		{"- だけの数", `[-]`, false},
		{"+ で始まる数", `[+1]`, false},
		{". のあとの数字が無い数", `[1.]`, false},
		{". で始まる数", `[.5]`, false},
		{"指数の数字が無い数", `[1e+]`, false},
		{"NaN", `[NaN]`, false},
		{"Infinity", `[-Infinity]`, false},
		{"途中で切れた true", `[tru]`, false},
		{"大文字の True", `[True]`, false},
		{"注釈", `{/*a*/}`, false},
		{"入れ子の深さ 501", nest(501), false},
		{"入れ子の深さ 500", nest(500), true},
		{"名前の長さ 50,000", name(strings.Repeat("a", 50000)), true},
		{"名前の長さ 50,001", name(strings.Repeat("a", 50001)), false},
		{"番号の \\u0041 は 1 バイトと数える", name(strings.Repeat(`\u0041`, 50000)), true},
		{"番号の \\u3042 は 3 バイトと数える", name(strings.Repeat(`\u3042`, 16667)), false},
		{"番号の組は 4 バイトと数える 50,000", name(strings.Repeat(`\uD83D\uDE00`, 12500)), true},
		{"番号の組は 4 バイトと数える 50,001", name(strings.Repeat(`\uD83D\uDE00`, 12500) + "a"), false},
		{"長く書いた字は書いたバイトで数える 50,000", name(strings.Repeat("\xc1\x81", 25000)), true},
		{"長く書いた字は書いたバイトで数える 50,001", name(strings.Repeat("\xc1\x81", 25000) + "a"), false},
		{"値の文字列は長さを数えない", `{"a":"` + strings.Repeat("a", 50001) + `"}`, true},
		{"空のオブジェクトと並び", ` { "a" : [ ] , "b" : { } } `, true},
		{"数の書き方", `[0,-0,10,-0.5,1e5,1E+5,2.5e-3]`, true},
		{"DEL はそのまま書ける", "\"\x7f\"", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			v, ok := parseJTree([]byte(c.in))
			if ok != c.ok {
				t.Fatalf("parseJTree(%q) の読めたか = %v, want %v", c.in, ok, c.ok)
			}
			if ok == (v == nil) {
				t.Errorf("parseJTree(%q) = %v, %v", c.in, v, ok)
			}
		})
	}
}

// TestParseJTree_TrailingIgnored は、parseJTree が最初の値だけを読み、そのあとの字を読まないことと、
// 6つの種類の値と、JSON に書かれた字のままの数を木に持つことを確かめる(要件4の受入基準6)。
// 「Java 版」と書いた場合は、Java 版が 201 で戻した本文の終わりの形である(testdata/backup/restore.json の
// trailing-garbage と trailing-object)。
func TestParseJTree_TrailingIgnored(t *testing.T) {
	const body = `{"o":{"s":"x"},"a":[1,-0.50e+010,true,false,null],"z":0}`
	const want = `{"a":[n:1,n:-0.50e+010,true,false,null],"o":{"s":"x"},"z":n:0}`
	for name, tail := range map[string]string{
		"Java 版 空白と語":       " xyz",
		"Java 版 2つ目のオブジェクト": `{"a":1}`,
		"閉じる字":              "}]",
		"読めないバイト":           "\xff",
		"空白だけ":              "\n",
	} {
		t.Run(name, func(t *testing.T) {
			if got := dumpJV(mustParseJTree(t, body+tail)); got != want {
				t.Errorf("parseJTree = %s, want %s", got, want)
			}
		})
	}
	t.Run("並び", func(t *testing.T) {
		if got := dumpJV(mustParseJTree(t, `["a"]x`)); got != `["a"]` {
			t.Errorf("parseJTree = %s", got)
		}
	})
}

// TestParseJTree_DuplicateKey は、parseJTree が、同じ名前の欄の値をすべて書かれた順に持ち、名前ごとのあとの値が分かることを
// 確かめる(要件4の受入基準6)。
// Java 版は、version を 0.9 のあとに 1.0 と書いた本文を 201 で戻し、1.0 のあとに 0.9 と書いた本文を
// 「サポートされていないバックアップバージョンです。」で断った(testdata/backup/restore.json の duplicate-version-later-valid と
// duplicate-version-later-invalid)。
func TestParseJTree_DuplicateKey(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"Java 版 あとの版が 1.0", `{"version":"0.9","x":1,"version":"1.0"}`, `{"version":"1.0","x":n:1}`},
		{"Java 版 あとの版が 0.9", `{"version":"1.0","version":"0.9"}`, `{"version":"0.9"}`},
		{"あとの値が null", `{"a":{"b":1},"a":null}`, `{"a":null}`},
		{"入れ子の中", `{"a":{"b":1,"b":[2]}}`, `{"a":{"b":[n:2]}}`},
		{"番号で書いた同じ名前", `{"a":1,"\u0061":2}`, `{"a":n:2}`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := dumpJV(mustParseJTree(t, c.in)); got != c.want {
				t.Errorf("parseJTree(%q) = %s, want %s", c.in, got, c.want)
			}
		})
	}

	// Java 版の Jackson は、同じ名前の欄の前の値も読み、前の値を読めない本文を断る(小タスク3.4 で Java 版に送った
	// {"version":{},"version":"1.0"})。readRestoreFile が前の値を確かめられるように、木は前の値も書かれた順に持つ。
	t.Run("前の値も書かれた順に持つ", func(t *testing.T) {
		v := mustParseJTree(t, `{"version":{},"x":1,"version":"1.0"}`)
		got := make([]string, len(v.members))
		for i, m := range v.members {
			got[i] = strconv.Quote(m.name) + ":" + dumpJV(m.value)
		}
		want := []string{`"version":{}`, `"x":n:1`, `"version":"1.0"`}
		if !slices.Equal(got, want) {
			t.Errorf("members = %q, want %q", got, want)
		}
	})
}
