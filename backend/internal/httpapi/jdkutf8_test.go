package httpapi

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"strings"
	"testing"
	"unicode/utf8"
)

// jdkUTF8Case は、testdata/jdkutf8/cases.json の1通りである。Java 版の答えの控えで、作り方は同じフォルダの README.md に書いた。
type jdkUTF8Case struct {
	Name             string   `json:"name"`
	InputHex         string   `json:"inputHex"`
	StoredHex        string   `json:"storedHex"`
	StoredCodePoints []string `json:"storedCodePoints"`
}

// readJDKUTF8Cases は、Java 版の答えの控えを読む。
func readJDKUTF8Cases(t *testing.T) []jdkUTF8Case {
	t.Helper()
	raw, err := fs.ReadFile(os.DirFS("testdata/jdkutf8"), "cases.json")
	if err != nil {
		t.Fatalf("Java 版の答えの控えを読めません: %v", err)
	}
	var file struct {
		Cases []jdkUTF8Case `json:"cases"`
	}
	if err := json.Unmarshal(raw, &file); err != nil {
		t.Fatalf("Java 版の答えの控えの JSON を読めません: %v", err)
	}
	if len(file.Cases) != 28 {
		t.Fatalf("Java 版の答えの控えの数 = %d, want 28", len(file.Cases))
	}
	return file.Cases
}

// replacementChar は、JDK が文字として読めないバイトの代わりに置く字 U+FFFD である。
const replacementChar = string(utf8.RuneError)

// codePoints は、文字列の字を1字ずつ U+XXXX の形にする。
func codePoints(s string) []string {
	out := []string{}
	for _, r := range s {
		out = append(out, fmt.Sprintf("U+%04X", r))
	}
	return out
}

// TestJDKUTF8_MatchesJava は、Java 版が PUT /api/users/me の username の部分を読んで保存した名前と、
// decodeJDKUTF8 の結果が、28通りのバイト列のすべてで同じになることを確かめる。
func TestJDKUTF8_MatchesJava(t *testing.T) {
	for _, c := range readJDKUTF8Cases(t) {
		t.Run(c.Name, func(t *testing.T) {
			input, err := hex.DecodeString(c.InputHex)
			if err != nil {
				t.Fatalf("inputHex を読めません: %v", err)
			}
			got := decodeJDKUTF8(input)
			if gotHex := hex.EncodeToString([]byte(got)); gotHex != c.StoredHex {
				t.Errorf("decodeJDKUTF8(%s) のバイト列 = %s, want %s", c.InputHex, gotHex, c.StoredHex)
			}
			if gotCP, wantCP := strings.Join(codePoints(got), " "), strings.Join(c.StoredCodePoints, " "); gotCP != wantCP {
				t.Errorf("decodeJDKUTF8(%s) の字 = %s, want %s", c.InputHex, gotCP, wantCP)
			}
		})
	}
}

// TestJDKUTF8_PrototypeExamples は、research.md の試作の記録の P8 の2つの例で、
// Java 版と同じ数の U+FFFD を返し、Go の標準の2つの置き換えとは違う数になることを確かめる。
func TestJDKUTF8_PrototypeExamples(t *testing.T) {
	tests := []struct {
		name      string
		input     []byte
		wantRepl  int
		goStdRepl int
	}{
		// Java 版は1つ。[]rune への変換は、誤ったバイトを1バイトずつ置き換えて2つにする
		{name: "3バイトの字の途中で切れる", input: []byte{0x61, 0xE3, 0x81, 0x62}, wantRepl: 1, goStdRepl: strings.Count(string([]rune(string([]byte{0x61, 0xE3, 0x81, 0x62}))), replacementChar)},
		// Java 版は4つ。strings.ToValidUTF8 は、続いた誤ったバイトをまとめて1つにする
		{name: "U+10FFFF を超える4バイト", input: []byte{0x61, 0xF4, 0x90, 0x80, 0x80, 0x62}, wantRepl: 4, goStdRepl: strings.Count(strings.ToValidUTF8(string([]byte{0x61, 0xF4, 0x90, 0x80, 0x80, 0x62}), replacementChar), replacementChar)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := decodeJDKUTF8(tt.input)
			if n := strings.Count(got, replacementChar); n != tt.wantRepl {
				t.Errorf("U+FFFD の数 = %d, want %d(結果 %q)", n, tt.wantRepl, got)
			}
			if tt.goStdRepl == tt.wantRepl {
				t.Errorf("Go の標準の置き換えの U+FFFD の数 %d が Java 版と同じなので、この例は違いを確かめていない", tt.goStdRepl)
			}
			if !strings.HasPrefix(got, "a") || !strings.HasSuffix(got, "b") {
				t.Errorf("前後の字が残っていない: %q", got)
			}
		})
	}
}

// TestJDKUTF8_ValidInputUnchanged は、UTF-8 として正しいバイト列を、そのままの字にすることを確かめる。
func TestJDKUTF8_ValidInputUnchanged(t *testing.T) {
	for _, s := range []string{"", "abc", "名前", "é", "\U0001F600絵文字", "\u0000\u007F", "\U0010FFFF"} {
		if got := decodeJDKUTF8([]byte(s)); got != s {
			t.Errorf("decodeJDKUTF8(%q) = %q, want 同じ", s, got)
		}
	}
}
