package resume

import (
	"errors"
	"fmt"
	"reflect"
	"strconv"
	"strings"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// exportBodyOrderDiffs は、TestExportBody_RejectRules の本文のうち、1つの欄に2つの文言が付く本文の名前と、
// 文言の並びの違いを載せた変えた動きの一覧の番号である。Java 版は Hibernate Validator の内部の順で並べ、
// Go 版は注釈の順に並べる。
var exportBodyOrderDiffs = map[string]string{
	"形式が空の文字列":     "CB-061",
	"出し方が空白だけ":     "CB-061",
	"フォント種類が空の文字列": "CB-061",
}

// TestExportBody_DiffTableInChangedBehaviors は、このファイルの表の番号が、すべて変えた動きの一覧にあることを確かめる。
func TestExportBody_DiffTableInChangedBehaviors(t *testing.T) {
	checkDiffTableInChangedBehaviors(t, exportBodyOrderDiffs)
	goReadDiffs := map[string]string{}
	for _, c := range exportBodyGoReadCases(t) {
		goReadDiffs[c.name] = c.cb
	}
	checkDiffTableInChangedBehaviors(t, goReadDiffs)
}

// validExportPDFBody は、断る条件に当たらない PDF の本文である。
const validExportPDFBody = `{"format":"pdf","disposition":"attachment","pdfSettings":{"fontFamily":"NotoSansJP",` +
	`"fontSizes":{"title":16,"date":10.5,"fullName":9.5,"sectionHeading":12},"tableHeaderColor":{"hex":"b4c7e7"}}}`

// exportPDFBody は、validExportPDFBody の old を new に替えた本文を返す。
func exportPDFBody(t *testing.T, old, new string) string {
	t.Helper()
	if !strings.Contains(validExportPDFBody, old) {
		t.Fatalf("本文に %s が無い", old)
	}
	return strings.Replace(validExportPDFBody, old, new, 1)
}

const (
	exportFontSizesPart = `"fontSizes":{"title":16,"date":10.5,"fullName":9.5,"sectionHeading":12}`
	exportColorPart     = `"tableHeaderColor":{"hex":"b4c7e7"}`
)

func describeString(s *string) string {
	if s == nil {
		return "nil"
	}
	return *s
}

func describeFloat(f *float64) string {
	if f == nil {
		return "nil"
	}
	return strconv.FormatFloat(*f, 'g', -1, 64)
}

func describeInt(n *int) string {
	if n == nil {
		return "nil"
	}
	return fmt.Sprint(*n)
}

// describeExportRequest は、読んだ本文を、比べやすい1行の字にする。
func describeExportRequest(r exportRequest) string {
	parts := []string{r.Format, r.Disposition}
	s := r.PDFSettings
	if s == nil {
		return strings.Join(parts, " ")
	}
	parts = append(parts, describeString(s.FontFamily))
	if z := s.FontSizes; z != nil {
		parts = append(parts, describeFloat(z.Title), describeFloat(z.Date), describeFloat(z.FullName), describeFloat(z.SectionHeading))
	} else {
		parts = append(parts, "fontSizes=nil")
	}
	if c := s.TableHeaderColor; c != nil {
		parts = append(parts, "hex="+describeString(c.Hex))
		if c.RGB != nil {
			parts = append(parts, "rgb="+describeInt(c.RGB.Red)+","+describeInt(c.RGB.Green)+","+describeInt(c.RGB.Blue))
		} else {
			parts = append(parts, "rgb=nil")
		}
	} else {
		parts = append(parts, "tableHeaderColor=nil")
	}
	return strings.Join(parts, " ")
}

// exportBodyWant は、本文への期待する答えである。unreadable なら本文が読めない誤り、errors が nil でなければ項目ごとの文言を
// 持つ入力の誤り、どちらでもなければ、読んだ本文を describeExportRequest で書いた字が request になることを期待する。
type exportBodyWant struct {
	unreadable bool
	errors     map[string][]string
	request    string
}

// checkExportBody は、本文 body を decodeExportBody で読んだ答えが want になることを確かめる。
func checkExportBody(t *testing.T, body string, want exportBodyWant) {
	t.Helper()
	req, err := decodeExportBody([]byte(body))
	var e *auth.Error
	if err != nil && !errors.As(err, &e) {
		t.Fatalf("誤り %v が auth.Error でない", err)
	}
	switch {
	case want.unreadable:
		if e == nil || e.Status != 400 || e.Message != "入力エラーがあります。" || len(e.Errors) != 0 {
			t.Errorf("答えが %+v %+v、期待は本文が読めない誤り", req, e)
		}
	case want.errors != nil:
		if e == nil || e.Status != 400 || e.Message != "入力エラーがあります。" || !reflect.DeepEqual(e.Errors, want.errors) {
			t.Errorf("答えが %+v %+v、期待は文言 %v", req, e, want.errors)
		}
	default:
		if e != nil {
			t.Fatalf("誤り %+v が返った、期待は %s", e, want.request)
		}
		if got := describeExportRequest(req); got != want.request {
			t.Errorf("読んだ本文が %s、期待は %s", got, want.request)
		}
	}
}

// TestExportBody_RejectRules は、Java 版の ExportResumeRequest の注釈の断る条件(入力必須、選べる値、PDF の設定の要否、
// 数の範囲、色の書き方)と、文言を付ける欄の名前と、1つの欄の2つの文言を注釈の順に並べることを確かめる(要件1の受入基準2、
// 要件3の受入基準1)。文言は、ExportResumeRequest.java の注釈の文字列を写した。
func TestExportBody_RejectRules(t *testing.T) {
	const okPDF = "pdf attachment NotoSansJP 16 10.5 9.5 12 hex=b4c7e7 rgb=nil"
	cases := []struct {
		name string
		body string
		want exportBodyWant
	}{
		{name: "PDF の正しい本文", body: validExportPDFBody, want: exportBodyWant{request: okPDF}},
		{name: "markdown で設定が無い", body: `{"format":"markdown","disposition":"inline"}`, want: exportBodyWant{request: "markdown inline"}},
		{
			name: "markdown でも設定を確かめる",
			body: strings.Replace(exportPDFBody(t, "NotoSansJP", "Arial"), `"pdf"`, `"markdown"`, 1),
			want: exportBodyWant{errors: map[string][]string{"pdfSettings.fontFamily": {"フォント種類が不正です。"}}},
		},
		{
			name: "形式が空の文字列",
			body: exportPDFBody(t, `"format":"pdf"`, `"format":""`),
			want: exportBodyWant{errors: map[string][]string{"format": {"エクスポート形式は入力必須です。", "エクスポート形式が不正です。"}}},
		},
		{
			name: "出し方が空白だけ",
			body: exportPDFBody(t, `"disposition":"attachment"`, `"disposition":" "`),
			want: exportBodyWant{errors: map[string][]string{"disposition": {"出力方法は入力必須です。", "出力方法が不正です。"}}},
		},
		{
			name: "形式と出し方が無い",
			body: `{}`,
			want: exportBodyWant{errors: map[string][]string{"format": {"エクスポート形式は入力必須です。"}, "disposition": {"出力方法は入力必須です。"}}},
		},
		{
			name: "PDF で設定が無い",
			body: `{"format":"pdf","disposition":"inline","pdfSettings":null}`,
			want: exportBodyWant{errors: map[string][]string{"pdfSettingsRequired": {"PDF設定は入力必須です。"}}},
		},
		{
			name: "フォント種類が空の文字列",
			body: exportPDFBody(t, `"NotoSansJP"`, `""`),
			want: exportBodyWant{errors: map[string][]string{"pdfSettings.fontFamily": {"フォント種類は入力必須です。", "フォント種類が不正です。"}}},
		},
		{
			name: "フォント種類が無い",
			body: exportPDFBody(t, `"fontFamily":"NotoSansJP",`, ``),
			want: exportBodyWant{errors: map[string][]string{"pdfSettings.fontFamily": {"フォント種類は入力必須です。"}}},
		},
		{
			name: "大きさと色が無い",
			body: `{"format":"pdf","disposition":"attachment","pdfSettings":{"fontFamily":"NotoSerifJP"}}`,
			want: exportBodyWant{errors: map[string][]string{
				"pdfSettings.fontSizes":        {"フォントサイズは入力必須です。"},
				"pdfSettings.tableHeaderColor": {"表ヘッダー色は入力必須です。"},
			}},
		},
		{
			name: "大きさの境の値",
			body: exportPDFBody(t, exportFontSizesPart, `"fontSizes":{"title":6,"date":72,"fullName":6.0,"sectionHeading":72.00}`),
			want: exportBodyWant{request: "pdf attachment NotoSansJP 6 72 6 72 hex=b4c7e7 rgb=nil"},
		},
		{
			name: "大きさの境の外",
			body: exportPDFBody(t, exportFontSizesPart, `"fontSizes":{"title":5.9999,"date":72.0001,"sectionHeading":null}`),
			want: exportBodyWant{errors: map[string][]string{
				"pdfSettings.fontSizes.title":          {"タイトルフォントサイズは6以上で入力してください。"},
				"pdfSettings.fontSizes.date":           {"日付フォントサイズは72以下で入力してください。"},
				"pdfSettings.fontSizes.fullName":       {"氏名フォントサイズは入力必須です。"},
				"pdfSettings.fontSizes.sectionHeading": {"セクション見出しフォントサイズは入力必須です。"},
			}},
		},
		{
			name: "赤と緑と青の誤り",
			body: exportPDFBody(t, exportColorPart, `"tableHeaderColor":{"rgb":{"r":-1,"b":256}}`),
			want: exportBodyWant{errors: map[string][]string{
				"pdfSettings.tableHeaderColor.rgb.red":   {"Rは0以上で入力してください。"},
				"pdfSettings.tableHeaderColor.rgb.green": {"Gは入力必須です。"},
				"pdfSettings.tableHeaderColor.rgb.blue":  {"Bは255以下で入力してください。"},
			}},
		},
		{
			name: "赤と緑と青の境の値",
			body: exportPDFBody(t, exportColorPart, `"tableHeaderColor":{"rgb":{"r":0,"g":255,"b":128}}`),
			want: exportBodyWant{request: "pdf attachment NotoSansJP 16 10.5 9.5 12 hex=nil rgb=0,255,128"},
		},
		{
			name: "hex の誤り",
			body: exportPDFBody(t, `"b4c7e7"`, `"abcdeg"`),
			want: exportBodyWant{errors: map[string][]string{"pdfSettings.tableHeaderColor.hex": {"カラーコードが不正です。"}}},
		},
		{
			name: "hex があり rgb が null",
			body: exportPDFBody(t, exportColorPart, `"tableHeaderColor":{"hex":"ABCDEF","rgb":null}`),
			want: exportBodyWant{request: "pdf attachment NotoSansJP 16 10.5 9.5 12 hex=ABCDEF rgb=nil"},
		},
		{
			name: "色が空のオブジェクト",
			body: exportPDFBody(t, exportColorPart, `"tableHeaderColor":{}`),
			want: exportBodyWant{errors: map[string][]string{"pdfSettings.tableHeaderColor.specifiedOnce": {"表ヘッダー色が不正です。"}}},
		},
		{
			name: "hex の誤りと両方がある",
			body: exportPDFBody(t, exportColorPart, `"tableHeaderColor":{"hex":"12345","rgb":{"r":1,"g":2,"b":3}}`),
			want: exportBodyWant{errors: map[string][]string{
				"pdfSettings.tableHeaderColor.hex":           {"カラーコードが不正です。"},
				"pdfSettings.tableHeaderColor.specifiedOnce": {"表ヘッダー色が不正です。"},
			}},
		},
		{name: "設定が数", body: `{"format":"pdf","disposition":"attachment","pdfSettings":1}`, want: exportBodyWant{unreadable: true}},
		{name: "前の重複が読めない", body: strings.Replace(validExportPDFBody, `{`, `{"format":["pdf"],`, 1), want: exportBodyWant{unreadable: true}},
		{name: "あとの重複を残す", body: strings.Replace(validExportPDFBody, `"format":"pdf"`, `"format":"pdf","format":"markdown"`, 1), want: exportBodyWant{request: "markdown attachment NotoSansJP 16 10.5 9.5 12 hex=b4c7e7 rgb=nil"}},
		{name: "知らない鍵", body: strings.Replace(validExportPDFBody, `{`, `{"x":[1,{"y":"z"}],`, 1), want: exportBodyWant{request: okPDF}},
		{
			name: "中の知らない鍵",
			body: strings.NewReplacer(`"title":16`, `"x":1,"title":16`, `{"hex"`, `{"x":1,"hex"`).Replace(validExportPDFBody),
			want: exportBodyWant{request: okPDF},
		},
		{
			name: "大きさと色が null",
			body: `{"format":"pdf","disposition":"attachment","pdfSettings":{"x":1,"fontFamily":"NotoSansJP","fontSizes":null,"tableHeaderColor":null}}`,
			want: exportBodyWant{errors: map[string][]string{
				"pdfSettings.fontSizes":        {"フォントサイズは入力必須です。"},
				"pdfSettings.tableHeaderColor": {"表ヘッダー色は入力必須です。"},
			}},
		},
		{name: "本文が JSON でない", body: `{"format":`, want: exportBodyWant{unreadable: true}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			checkExportBody(t, c.body, c.want)
			twoMessages := false
			for _, messages := range c.want.errors {
				twoMessages = twoMessages || len(messages) > 1
			}
			if _, inTable := exportBodyOrderDiffs[c.name]; inTable != twoMessages {
				t.Errorf("本文 %s は、1つの欄に2つの文言が付くか(%v)と、文言の並びの表にあるか(%v)が合わない", c.name, twoMessages, inTable)
			}
		})
	}
	for name := range exportBodyOrderDiffs {
		found := false
		for _, c := range cases {
			found = found || c.name == name
		}
		if !found {
			t.Errorf("文言の並びの表の本文 %s が無い", name)
		}
	}
}

// exportBodyGoReadCase は、Java 版と答えが違う本文と、Go 版の答えと、違いを載せた変えた動きの一覧の番号である。
type exportBodyGoReadCase struct {
	name string
	cb   string
	body string
	want exportBodyWant
}

// exportBodyGoReadCases は、encoding/json の決まりで読むので Java 版と答えが違う本文を返す。
func exportBodyGoReadCases(t *testing.T) []exportBodyGoReadCase {
	const okPDF = "pdf attachment NotoSansJP 16 10.5 9.5 12 hex=b4c7e7 rgb=nil"
	rgb := func(r, g, b string) string {
		return exportPDFBody(t, exportColorPart, `"tableHeaderColor":{"rgb":{"r":`+r+`,"g":`+g+`,"b":`+b+`}}`)
	}
	unreadable := exportBodyWant{unreadable: true}
	manyDigits := strings.Repeat("1", 1001)
	return []exportBodyGoReadCase{
		{name: "赤が小数", cb: "CB-102", body: rgb("12.7", "0", "0"), want: unreadable},
		{name: "緑が指数の付いた数", cb: "CB-102", body: rgb("0", "1E1", "0"), want: unreadable},
		{name: "青が文字列", cb: "CB-102", body: rgb("0", "0", `"12"`), want: unreadable},
		{
			name: "赤が Java の int に入らない整数", cb: "CB-102", body: rgb("2147483648", "0", "0"),
			want: exportBodyWant{errors: map[string][]string{"pdfSettings.tableHeaderColor.rgb.red": {"Rは255以下で入力してください。"}}},
		},
		{name: "大きさが文字列", cb: "CB-103", body: exportPDFBody(t, `"title":16`, `"title":"16"`), want: unreadable},
		{name: "大きさが float64 に入らない数", cb: "CB-103", body: exportPDFBody(t, `"title":16`, `"title":1e400`), want: unreadable},
		{
			name: "大きさが float64 で表せない桁の数", cb: "CB-103",
			body: exportPDFBody(t, `"title":16`, `"title":72.0000000000000000001`),
			want: exportBodyWant{request: "pdf attachment NotoSansJP 72 10.5 9.5 12 hex=b4c7e7 rgb=nil"},
		},
		{name: "16進数の色が数", cb: "CB-104", body: exportPDFBody(t, `"b4c7e7"`, `123456`), want: unreadable},
		{name: "形式が真偽", cb: "CB-104", body: exportPDFBody(t, `"format":"pdf"`, `"format":true`), want: unreadable},
		{name: "出し方が数", cb: "CB-104", body: exportPDFBody(t, `"attachment"`, `1E1`), want: unreadable},
		{name: "フォント種類が数", cb: "CB-104", body: exportPDFBody(t, `"NotoSansJP"`, `1e2`), want: unreadable},
		{name: "鍵の大文字と小文字が違う", cb: "CB-105", body: exportPDFBody(t, `"format"`, `"Format"`), want: exportBodyWant{request: okPDF}},
		{name: "本文のあとに字が続く", cb: "CB-106", body: validExportPDFBody + " x", want: unreadable},
		{
			name: "本文が null だけ", cb: "CB-107", body: `null`,
			want: exportBodyWant{errors: map[string][]string{"format": {"エクスポート形式は入力必須です。"}, "disposition": {"出力方法は入力必須です。"}}},
		},
		{
			name: "知らない欄の数字が1000字を超える", cb: "CB-108",
			body: strings.Replace(validExportPDFBody, `{`, `{"x":`+manyDigits+`,`, 1), want: exportBodyWant{request: okPDF},
		},
		{
			name: "大きさの数字が1000字を超える", cb: "CB-108",
			body: exportPDFBody(t, `"title":16`, `"title":16.`+strings.Repeat("0", 1000)), want: exportBodyWant{request: okPDF},
		},
	}
}

// TestExportBody_GoReads は、Java 版と答えが違う本文を、Go 版が encoding/json の決まりで読むことを確かめる。
// 違いは、変えた動きの一覧の CB-102 から CB-108 に載せた。
func TestExportBody_GoReads(t *testing.T) {
	for _, c := range exportBodyGoReadCases(t) {
		t.Run(c.name, func(t *testing.T) {
			checkExportBody(t, c.body, c.want)
		})
	}
}
