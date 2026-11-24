package resume

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

// TestJavaJSON_Escapes は、JavaJSON が、Java 版がそのまま書く字をそのまま書き、番号で書く字を番号で書くことを確かめる
// (要件3の受入基準3)。期待する字の並びは、Java 版が書き出したファイル compat/fixtures/backups/java-804.json と、
// Java 版の戻しの答えを控えた testdata/backup/restore.json の字の並びである。
// 対になっていないサロゲートは、Go の文字列では、UTF-8 と同じ規則の3バイト(WTF-8)で持つ。
func TestJavaJSON_Escapes(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"引用符", `"`, `"\""`},
		{"逆斜線", `\`, `"\\"`},
		{"短い形で書く制御の字", "\b\t\n\f\r", `"\b\t\n\f\r"`},
		{"ほかの0x20より小さい字は大文字の16進数の番号で書く", "\x00\x01\x0b\x1a\x1f", `"\u0000\u0001\u000B\u001A\u001F"`},
		{"BMP の外の字はサロゲートの組の番号で書く", "\U0001F600\U00020BB7", `"\uD83D\uDE00\uD842\uDFB7"`},
		{"対になっていない前の半分のサロゲート", "a\xed\xa0\x80b", `"a\uD800b"`},
		{"対になっていない後ろの半分のサロゲート", "\xed\xb0\x80", `"\uDC00"`},
		{"続けて並んだ2つのサロゲート", "\xed\xbf\xbf\xed\xa0\x80", `"\uDFFF\uD800"`},
		{"HTML の記号と斜線はそのまま書く", `<>&'/`, `"<>&'/"`},
		{"U+007F と U+0085 はそのまま書く", "\u007f\u0085", "\"\u007f\u0085\""},
		{"行と段落の区切りはそのまま書く", "\u2028\u2029", "\"\u2028\u2029\""},
		{"日本語と空白はそのまま書く", "経歴書 の名前", `"経歴書 の名前"`},
		{"空の字", "", `""`},
		{"UTF-8 として読めないバイトは U+FFFD にする", "a\xffb", "\"a�b\""},
		// java-804.json の経歴書の名前の字の並び。U+2028 と U+2029 は、Java 版のファイルでもそのまま書かれている
		{"Java 版が書き出した経歴書の名前", "記号<>&\"'と\n改行\tタブ\U0001F600\u2028\u2029の経歴書", "\"記号<>&\\\"'と\\n改行\\tタブ\\uD83D\\uDE00\u2028\u2029の経歴書\""},
		// restore.json の、Java 版の戻しの答えの本文の字の並び
		{"Java 版の答えの制御の字", "経歴書の\x01名前", `"経歴書の\u0001名前"`},
		{"Java 版の答えのサロゲート", "強み\xed\xa0\x80の中身", `"強み\uD800の中身"`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := string(JavaJSON(c.in)); got != c.want {
				t.Errorf("JavaJSON(%q) = %s, want %s", c.in, got, c.want)
			}
		})
	}
}

type javaJSONMarshaler struct{ s string }

func (m javaJSONMarshaler) MarshalJSON() ([]byte, error) {
	if m.s == "誤り" {
		return nil, errors.New("書けません")
	}
	return []byte(m.s), nil
}

type javaJSONInner struct {
	Languages []string `json:"languages,omitempty"`
	Tools     []string `json:"tools,omitempty"`
}

type javaJSONSample struct {
	Zeta       string              `json:"zeta"`
	Alpha      int                 `json:"alpha"`
	Unsigned   uint8               `json:"unsigned"`
	Name       *string             `json:"name,omitempty"`
	Empty      *string             `json:"empty,omitempty"`
	NilPtr     *string             `json:"nilPtr"`
	Flag       bool                `json:"flag"`
	OmitFlag   bool                `json:"omitFlag,omitempty"`
	OmitText   string              `json:"omitText,omitempty"`
	OmitNumber int                 `json:"omitNumber,omitempty"`
	OmitSlice  []string            `json:"omitSlice,omitempty"`
	OmitEmpty  []string            `json:"omitEmpty,omitempty"`
	NilSlice   []string            `json:"nilSlice"`
	EmptySlice []string            `json:"emptySlice"`
	PtrItems   []*string           `json:"ptrItems"`
	Array      [2]int              `json:"array"`
	Inner      javaJSONInner       `json:"inner,omitempty"`
	InnerPtr   *javaJSONInner      `json:"innerPtr"`
	Any        any                 `json:"any"`
	NilAny     any                 `json:"nilAny"`
	Marshaler  javaJSONMarshaler   `json:"marshaler"`
	Marshalers []javaJSONMarshaler `json:"marshalers"`
	NilMarsh   *javaJSONMarshaler  `json:"nilMarsh"`
	NoTag      string
	Skipped    string `json:"-"`
	unexported string
}

// TestJavaJSON_OmitEmptyAndMarshaler は、JavaJSON が、構造体の欄を宣言の順に、json のタグの名前と omitempty に従って書き、
// json.Marshaler を持つ値をその書き方で書くことを確かめる(要件3の受入基準1の、Java 版が書かない欄を書かないこと)。
// 値の無い欄を書かないことは、Java 版が書き出したファイル java-804.json の、endDate の無い項目と、"infrastructure":{} の
// 値の無い技術の分類の書き方と同じである。
func TestJavaJSON_OmitEmptyAndMarshaler(t *testing.T) {
	name, empty, item := "鈴木", "", "Go"
	v := javaJSONSample{
		Zeta: "z", Alpha: -12, Unsigned: 200, Name: &name, Empty: &empty, Flag: false,
		OmitEmpty:  []string{},
		EmptySlice: []string{},
		PtrItems:   []*string{&item, nil},
		Array:      [2]int{1, 2},
		Inner:      javaJSONInner{},
		InnerPtr:   &javaJSONInner{Languages: []string{"TypeScript"}},
		Any:        "<値>",
		Marshaler:  javaJSONMarshaler{s: "{ \"a\" : [1, 2],\n \"b\" : \"x y\" }"},
		Marshalers: []javaJSONMarshaler{{s: `"2026-11"`}},
		NoTag:      "t", Skipped: "s", unexported: "u",
	}
	want := `{"zeta":"z","alpha":-12,"unsigned":200,"name":"鈴木","empty":"","nilPtr":null,"flag":false,` +
		`"nilSlice":null,"emptySlice":[],"ptrItems":["Go",null],"array":[1,2],"inner":{},` +
		`"innerPtr":{"languages":["TypeScript"]},"any":"<値>","nilAny":null,"marshaler":{"a":[1,2],"b":"x y"},` +
		`"marshalers":["2026-11"],"nilMarsh":null,"NoTag":"t"}`
	if got := string(JavaJSON(v)); got != want {
		t.Errorf("JavaJSON =\n%s\nwant\n%s", got, want)
	}

	t.Run("構造体のポインタと nil", func(t *testing.T) {
		if got := string(JavaJSON(&javaJSONInner{Tools: []string{"Git"}})); got != `{"tools":["Git"]}` {
			t.Errorf("JavaJSON = %s", got)
		}
		if got := string(JavaJSON(nil)); got != "null" {
			t.Errorf("JavaJSON(nil) = %s", got)
		}
	})

	t.Run("特別な字の無い値は encoding/json と同じに書く", func(t *testing.T) {
		v := javaJSONSample{Zeta: "plain", NilSlice: []string{"a"}, Marshaler: javaJSONMarshaler{s: "1"}}
		want, err := json.Marshal(v)
		if err != nil {
			t.Fatal(err)
		}
		if got := JavaJSON(v); string(got) != string(want) {
			t.Errorf("JavaJSON = %s, want %s", got, want)
		}
	})

	t.Run("書けない値は panic する", func(t *testing.T) {
		type embedded struct{ javaJSONInner }
		for name, v := range map[string]any{
			"Marshaler の誤り":       javaJSONMarshaler{s: "誤り"},
			"Marshaler の誤った JSON": javaJSONMarshaler{s: "{"},
			"小数":                  1.5,
			"対応表":                 map[string]string{"a": "b"},
			"埋め込みの欄":              embedded{},
		} {
			t.Run(name, func(t *testing.T) {
				defer func() {
					r := recover()
					if r == nil {
						t.Fatal("panic しませんでした")
					}
					if !strings.HasPrefix(fmtPanic(r), "resume: JavaJSON") {
						t.Errorf("panic の値 = %v", r)
					}
				}()
				JavaJSON(v)
			})
		}
	})
}

func fmtPanic(r any) string {
	if err, ok := r.(error); ok {
		return err.Error()
	}
	return ""
}
