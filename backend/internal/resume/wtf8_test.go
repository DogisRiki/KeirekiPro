package resume

import (
	"reflect"
	"slices"
	"testing"
	"time"
)

// TestWTF8_JavaLen は、javaLen が、WTF-8 の字を Java の文字列の長さと同じ数え方で数えることを確かめる(要件4の受入基準5)。
// Java の文字列の長さは UTF-16 の単位の数なので、BMP の外の字を2、対になっていないサロゲートを1と数える。
// wtf8Units の並びは、parseJTree が字を読んだときの UTF-16 の単位の並びと同じである。
func TestWTF8_JavaLen(t *testing.T) {
	cases := []struct {
		name  string
		in    string
		units []uint16
	}{
		{"空の字", "", []uint16{}},
		{"ASCII", "abc", []uint16{'a', 'b', 'c'}},
		{"BMP の中の字は1", "経歴", []uint16{0x7D4C, 0x6B74}},
		{"BMP の外の字は2", "😀", []uint16{0xD83D, 0xDE00}},
		{"対になっていない前の半分は1", "\xed\xa0\x80", []uint16{0xD800}},
		{"対になっていない後ろの半分は1", "\xed\xbf\xbf", []uint16{0xDFFF}},
		{"続けて並んだ2つのサロゲート", "\xed\xb0\x80\xed\xa0\x80", []uint16{0xDC00, 0xD800}},
		{"混ぜた字", "a\xed\xa0\x80𠮷\xed\xb0\x80", []uint16{'a', 0xD800, 0xD842, 0xDFB7, 0xDC00}},
		{"U+FFFF", "\xef\xbf\xbf", []uint16{0xFFFF}},
		{"UTF-8 として読めないバイトは U+FFFD の1", "a\xffb", []uint16{'a', 0xFFFD, 'b'}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := wtf8Units(c.in); !slices.Equal(got, c.units) {
				t.Errorf("wtf8Units(%q) = %X, want %X", c.in, got, c.units)
			}
			if got := javaLen(c.in); got != len(c.units) {
				t.Errorf("javaLen(%q) = %d, want %d", c.in, got, len(c.units))
			}
		})
	}

	t.Run("parseJTree が読んだ字の単位に戻る", func(t *testing.T) {
		for _, body := range []string{`"x\uD800y"`, `"\uDBFF\uD800"`, `"\uD83D\uDE00経歴"`, "\"a\xf5\x80\x80\x80\""} {
			v := mustParseJTree(t, body)
			if got := wtf8FromUnits(wtf8Units(v.text)); got != v.text {
				t.Errorf("wtf8FromUnits(wtf8Units(%q)) = %q", v.text, got)
			}
		}
	})
}

// TestWTF8_ToDBText は、toDBText が、対になっていないサロゲートを1つずつ ? にし、ほかの字を変えないことを確かめる
// (要件2の受入基準1)。PostgreSQL の UTF-8 の列は対になっていないサロゲートを入れられず、Java 版は、対になっていない
// サロゲートを ? にした字をデータベースに入れた(research.md の試作の記録の chars-lone)。
func TestWTF8_ToDBText(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"前の半分", "a\xed\xa0\x80b", "a?b"},
		{"後ろの半分", "\xed\xbf\xbf", "?"},
		{"続けて並んだ2つのサロゲートは2つの ?", "\xed\xbf\xbf\xed\xa0\x80", "??"},
		{"Java 版の答えのサロゲート", "強み\xed\xa0\x80の中身", "強み?の中身"},
		{"組になった字は変えない", "😀𠮷", "😀𠮷"},
		{"ほかの字は変えない", "経歴書 <>&\"'\n\t\x01\u2028", "経歴書 <>&\"'\n\t\x01\u2028"},
		{"空の字", "", ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := toDBText(c.in); got != c.want {
				t.Errorf("toDBText(%q) = %q, want %q", c.in, got, c.want)
			}
		})
	}
}

// loneText は、TestWTF8_DBResumeAllFields が字の欄に入れる、対になっていないサロゲートを含む字である。
const loneText = "x\xed\xa0\x80y"

// fillStrings は、v の中のすべての字の欄、字のポインタ、構造体と並びの要素に loneText を入れる。
// 構造体の並びと字のポインタの並びは、2つの要素の並びにする。字のポインタの並びの2つ目の要素は nil にする。
func fillStrings(v reflect.Value) {
	switch v.Kind() {
	case reflect.String:
		v.SetString(loneText)
	case reflect.Pointer:
		if v.Type().Elem().Kind() == reflect.String {
			s := loneText
			v.Set(reflect.ValueOf(&s))
		}
	case reflect.Slice:
		v.Set(reflect.MakeSlice(v.Type(), 2, 2))
		if v.Type().Elem().Kind() == reflect.Pointer {
			fillStrings(v.Index(0))
			return
		}
		for i := range v.Len() {
			fillStrings(v.Index(i))
		}
	case reflect.Struct:
		if v.Type() == reflect.TypeFor[time.Time]() {
			return
		}
		for i := range v.NumField() {
			fillStrings(v.Field(i))
		}
	default:
	}
}

// collectStrings は、v の中のすべての字を、欄の道のりを付けて集める。nil の字のポインタと nil の並びは、そのことを集める。
func collectStrings(v reflect.Value, path string, out map[string]string) {
	switch v.Kind() {
	case reflect.String:
		out[path] = v.String()
	case reflect.Pointer:
		if v.IsNil() {
			if v.Type().Elem().Kind() == reflect.String {
				out[path] = "<nil>"
			}
			return
		}
		collectStrings(v.Elem(), path, out)
	case reflect.Slice:
		if v.IsNil() {
			out[path] = "<nil の並び>"
			return
		}
		for i := range v.Len() {
			collectStrings(v.Index(i), path+"["+string(rune('0'+i))+"]", out)
		}
	case reflect.Struct:
		if v.Type() == reflect.TypeFor[time.Time]() {
			return
		}
		for i := range v.NumField() {
			collectStrings(v.Field(i), path+"."+v.Type().Field(i).Name, out)
		}
	default:
	}
}

// TestWTF8_DBResumeAllFields は、dbResume が、経歴書と6つの欄の項目のすべての字の欄に toDBText を当てることを確かめる
// (要件2の受入基準1)。テストは、経歴書の型のすべての字の欄を型から数えて、対になっていないサロゲートを入れる。
// そのため、経歴書の型に字の欄が増えて dbResume が直し忘れると、このテストが失敗する。
func TestWTF8_DBResumeAllFields(t *testing.T) {
	var in Resume
	fillStrings(reflect.ValueOf(&in).Elem())
	before := map[string]string{}
	collectStrings(reflect.ValueOf(in), "Resume", before)

	got := dbResume(in)
	after := map[string]string{}
	collectStrings(reflect.ValueOf(got), "Resume", after)

	// 字の欄の数: 経歴書3、職歴2×1、プロジェクト2×(6と技術スタック35×2)、資格2×1、ポートフォリオ2×4、SNS 2×2、自己PR 2×2
	const wantFields = 3 + 2 + 2*(6+35*2) + 2 + 2*4 + 2*2 + 2*2
	if len(after) != wantFields || len(before) != wantFields {
		t.Fatalf("字の欄の数 = %d と %d, want %d", len(before), len(after), wantFields)
	}
	for path, s := range after {
		want := "x?y"
		if before[path] == "<nil>" {
			want = "<nil>"
		}
		if s != want {
			t.Errorf("%s = %q, want %q", path, s, want)
		}
	}
	nils := 0
	for path, s := range before {
		switch s {
		case loneText:
		case "<nil>":
			nils++
		default:
			t.Errorf("dbResume が渡した経歴書の %s を %q に変えました", path, s)
		}
	}
	if nils != 2*35 {
		t.Errorf("技術スタックの nil の要素の数 = %d, want %d", nils, 2*35)
	}

	t.Run("nil と空の並びとほかの欄を変えない", func(t *testing.T) {
		name := "名前"
		r := Resume{
			Name: "経歴書", Date: Date{Year: 2026, Month: time.November, Day: 24}, LastName: nil, FirstName: &name,
			CreatedAt: time.Date(2026, 11, 24, 1, 2, 3, 0, time.UTC),
			Projects: []Project{{
				Name: "案件", Period: Period{StartDate: YearMonth{Year: 2024, Month: time.April}, Active: true},
				Process:   Process{Implementation: true},
				TechStack: TechStack{Frontend: FrontendStacks[*string]{Languages: []*string{}}},
			}},
			Portfolios: []Portfolio{{Name: "作品", TechStack: nil}},
		}
		got := dbResume(r)
		if !reflect.DeepEqual(got, r) {
			t.Errorf("dbResume =\n%+v\nwant\n%+v", got, r)
		}
		if got.Careers != nil || got.Projects[0].TechStack.Backend.Languages != nil || got.Projects[0].TechStack.Frontend.Languages == nil {
			t.Errorf("nil と空の並びが入れ替わりました: %+v", got)
		}
	})
}
