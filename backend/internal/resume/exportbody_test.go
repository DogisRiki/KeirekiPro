package resume

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"os"
	"reflect"
	"regexp"
	"strings"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// exportBodyCase は、小タスク1.2 で控えた testdata/export/body.json の1つの本文と、Java 版の答えである。
type exportBodyCase struct {
	Name        string `json:"name"`
	Body        string `json:"body"`
	Status      int    `json:"status"`
	ContentType string `json:"contentType"`
	Disposition string `json:"disposition"`
	Response    *struct {
		Message string              `json:"message"`
		Errors  map[string][]string `json:"errors"`
	} `json:"response"`
}

// exportResult は、本文への答えのうち、比べる部分である。Disposition は、PDF の 200 の答えだけが持つ。
type exportResult struct {
	Status      int
	ContentType string
	Disposition string
	Message     string
	Errors      map[string][]string
}

func (r exportResult) String() string {
	return fmt.Sprintf("%d %s %s %s %v", r.Status, r.ContentType, r.Disposition, r.Message, r.Errors)
}

// exportContentTypes は、形式ごとの、200 の答えの Content-Type である。
var exportContentTypes = map[string]string{"pdf": "application/pdf", "markdown": "text/markdown;charset=utf-8"}

// goExportResult は、本文を decodeExportBody で読み、PDF なら normalizePDFSettings で設定を直して、Go 版の答えを作る。
func goExportResult(body []byte) exportResult {
	req, err := decodeExportBody(body)
	if err == nil && req.Format == "pdf" {
		_, err = normalizePDFSettings(*req.PDFSettings)
	}
	if err != nil {
		var e *auth.Error
		if !errors.As(err, &e) {
			return exportResult{Message: err.Error()}
		}
		return exportResult{Status: e.Status, ContentType: "application/json", Message: e.Message, Errors: e.Errors}
	}
	r := exportResult{Status: 200, ContentType: exportContentTypes[req.Format]}
	if req.Format == "pdf" {
		r.Disposition = req.Disposition
	}
	return r
}

// javaExportResult は、正解のファイルの Java 版の答えである。
func javaExportResult(c exportBodyCase) exportResult {
	r := exportResult{Status: c.Status, ContentType: c.ContentType, Disposition: c.Disposition}
	if c.Response != nil {
		r.Message, r.Errors = c.Response.Message, c.Response.Errors
	}
	return r
}

// exportBodyDiffs は、body.json の本文のうち、Go 版の答えが Java 版と違う本文の名前と、その違いを載せた変えた動きの一覧の番号である。
// いまは、どの本文の答えも Java 版と同じなので、空にする。
var exportBodyDiffs = map[string]string{}

// exportBodyOrderDiffs は、TestExportBody_RejectRules の本文のうち、1つの欄に2つの文言が付く本文の名前と、
// 文言の並びの違いを載せた変えた動きの一覧の番号である。Java 版は Hibernate Validator の内部の順で並べ、
// Go 版は注釈の順に並べる。
var exportBodyOrderDiffs = map[string]string{
	"形式が空の文字列":     "CB-061",
	"出し方が空白だけ":     "CB-061",
	"フォント種類が空の文字列": "CB-061",
}

var (
	screenNumber  = regexp.MustCompile(`^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$`)
	screenInteger = regexp.MustCompile(`^-?(0|[1-9][0-9]*)$`)
)

// screenExportSchema は、画面が送る本文の鍵と値の書き方である。値は、"string"(文字列)、"number"(数)、"integer"(整数)、
// または中のオブジェクトの書き方である。
var screenExportSchema = map[string]any{
	"format":      "string",
	"disposition": "string",
	"pdfSettings": map[string]any{
		"fontFamily": "string",
		"fontSizes":  map[string]any{"title": "number", "date": "number", "fullName": "number", "sectionHeading": "number"},
		"tableHeaderColor": map[string]any{
			"hex": "string",
			"rgb": map[string]any{"r": "integer", "g": "integer", "b": "integer"},
		},
	},
}

// screenExportBody は、本文が、画面が送る書き方かを返す。画面は、正しい JSON の本文に、決まった鍵を1つずつ書き、
// 文字列の欄に文字列を、文字の大きさの欄に数を、赤と緑と青の欄に整数を入れる。
func screenExportBody(body []byte) bool {
	return json.Valid(body) && screenExportObject(screenExportSchema, body)
}

func screenExportObject(schema map[string]any, raw []byte) bool {
	dec := json.NewDecoder(bytes.NewReader(raw))
	if tok, err := dec.Token(); err != nil || tok != json.Delim('{') {
		return false
	}
	seen := map[string]bool{}
	for dec.More() {
		tok, err := dec.Token()
		if err != nil {
			return false
		}
		key, _ := tok.(string)
		var v json.RawMessage
		if dec.Decode(&v) != nil {
			return false
		}
		want, known := schema[key]
		if !known || seen[key] {
			return false
		}
		seen[key] = true
		var ok bool
		switch w := want.(type) {
		case map[string]any:
			ok = screenExportObject(w, v)
		case string:
			s := string(v)
			ok = w == "string" && strings.HasPrefix(s, `"`) || w == "number" && screenNumber.MatchString(s) || w == "integer" && screenInteger.MatchString(s)
		}
		if !ok {
			return false
		}
	}
	return true
}

func loadExportBodyJSON(t *testing.T) []exportBodyCase {
	t.Helper()
	b, err := os.ReadFile("testdata/export/body.json")
	if err != nil {
		t.Fatal(err)
	}
	var cases []exportBodyCase
	if err := json.Unmarshal(b, &cases); err != nil {
		t.Fatal(err)
	}
	if len(cases) == 0 {
		t.Fatal("testdata/export/body.json に本文が無い")
	}
	return cases
}

// TestExportBody_MatchesJava は、小タスク1.2 で控えた body.json のすべての本文で、Go 版の答え(状態の番号、Content-Type、
// PDF の出し方、文言)が Java 版と同じか、違いが変えた動きの一覧に載っていることを確かめる(要件1の受入基準1と2、要件3の受入基準1)。
// 画面が送る書き方の本文は、答えが Java 版と同じでなければならない。
func TestExportBody_MatchesJava(t *testing.T) {
	cases := loadExportBodyJSON(t)
	names := map[string]bool{}
	screens := 0
	for _, c := range cases {
		names[c.Name] = true
		screen := screenExportBody([]byte(c.Body))
		if screen {
			screens++
		}
		got, want := goExportResult([]byte(c.Body)), javaExportResult(c)
		id, inTable := exportBodyDiffs[c.Name]
		same := reflect.DeepEqual(got, want)
		switch {
		case same && inTable:
			t.Errorf("本文 %s: Go 版の答えは Java 版と同じ %s なのに、表に %s がある", c.Name, got, id)
		case !same && !inTable:
			t.Errorf("本文 %s: Go 版の答え %s が Java 版の答え %s と違うのに、表に無い", c.Name, got, want)
		case !same && screen:
			t.Errorf("本文 %s は画面が送る書き方なのに、Go 版の答え %s が Java 版の答え %s と違う", c.Name, got, want)
		}
	}
	if screens == 0 {
		t.Fatal("画面が送る書き方の本文が無い")
	}
	for name := range exportBodyDiffs {
		if !names[name] {
			t.Errorf("表の本文 %s が body.json に無い", name)
		}
	}
}

// TestExportBody_DiffTableInChangedBehaviors は、このファイルの表の番号が、すべて変えた動きの一覧にあることを確かめる。
func TestExportBody_DiffTableInChangedBehaviors(t *testing.T) {
	table := map[string]string{}
	for _, m := range []map[string]string{exportBodyDiffs, exportBodyOrderDiffs} {
		for name, id := range m {
			table[name] = id
		}
	}
	checkDiffTableInChangedBehaviors(t, table)
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

func describeRat(r *big.Rat) string {
	if r == nil {
		return "nil"
	}
	return r.RatString()
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
		parts = append(parts, describeRat(z.Title), describeRat(z.Date), describeRat(z.FullName), describeRat(z.SectionHeading))
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
	const okPDF = "pdf attachment NotoSansJP 16 21/2 19/2 12 hex=b4c7e7 rgb=nil"
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
			body: exportPDFBody(t, exportFontSizesPart, `"fontSizes":{"title":6,"date":72,"fullName":"6.0","sectionHeading":72.00}`),
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
			body: exportPDFBody(t, exportColorPart, `"tableHeaderColor":{"rgb":{"r":0,"g":255,"b":"128"}}`),
			want: exportBodyWant{request: "pdf attachment NotoSansJP 16 21/2 19/2 12 hex=nil rgb=0,255,128"},
		},
		{
			name: "hex の誤り",
			body: exportPDFBody(t, `"b4c7e7"`, `"abcdeg"`),
			want: exportBodyWant{errors: map[string][]string{"pdfSettings.tableHeaderColor.hex": {"カラーコードが不正です。"}}},
		},
		{
			name: "hex があり rgb が null",
			body: exportPDFBody(t, exportColorPart, `"tableHeaderColor":{"hex":"ABCDEF","rgb":null}`),
			want: exportBodyWant{request: "pdf attachment NotoSansJP 16 21/2 19/2 12 hex=ABCDEF rgb=nil"},
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
		{name: "あとの重複を残す", body: strings.Replace(validExportPDFBody, `"format":"pdf"`, `"format":"pdf","format":"markdown"`, 1), want: exportBodyWant{request: "markdown attachment NotoSansJP 16 21/2 19/2 12 hex=b4c7e7 rgb=nil"}},
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

// TestExportBody_ReadsJacksonValues は、本文の値を、Java 版の Jackson 3.1.7 と同じに読むことを確かめる(要件1の受入基準1)。
// 期待する値は、JDK 21 で Jackson 3.1.7 を動かし、Integer と BigDecimal と String の欄に同じ値を読ませて確かめた。
// 文字の大きさの欄の 1000 と 0 は、Java の値をそのまま持たず、6 と 72 と比べた結果が同じになる値に替えた値である。
func TestExportBody_ReadsJacksonValues(t *testing.T) {
	ints := []struct{ raw, want string }{
		{`"\t12"`, "12"},
		{`"\u000b12"`, "12"},
		{`"  12  "`, "12"},
		{`"+12"`, "12"},
		{`"-12"`, "-12"},
		{`"-0"`, "0"},
		{`"١٢"`, "12"},
		{`"௧௨"`, "12"},
		{`"１２"`, "12"},
		{`2147483647.0000001`, "2147483647"},
		{`1e9`, "1000000000"},
		{`-0.0`, "0"},
		{`-0.9`, "0"},
		{`255.9`, "255"},
		{`""`, "nil"},
		{`" "`, "nil"},
		{`"null"`, "nil"},
		{`null`, "nil"},
		{`" 12"`, "error"},
		{`"NULL"`, "error"},
		{`"𝟏"`, "error"},
		{`"12.7"`, "error"},
		{`"12e0"`, "error"},
		{`"1_0"`, "error"},
		{`"+"`, "error"},
		{`"-"`, "error"},
		{`"+-1"`, "error"},
		{`"2147483648"`, "error"},
		{`"99999999999"`, "error"},
		{`2147483647.5`, "error"},
		{`-2147483648.9`, "error"},
		{`1.5e300`, "error"},
		{`1e400`, "error"},
		{`99999999999999999999`, "error"},
		{`true`, "error"},
		{`[12]`, "error"},
		{`{}`, "error"},
	}
	for _, c := range ints {
		n, ok := readJavaInt(json.RawMessage(c.raw))
		got := describeInt(n)
		if !ok {
			got = "error"
		}
		if got != c.want {
			t.Errorf("整数の欄の %s を %s と読んだ、Jackson は %s", c.raw, got, c.want)
		}
	}
	decimals := []struct{ raw, want string }{
		{`"+.5e2"`, "50"},
		{`"-.5"`, "-1/2"},
		{`"1e+05"`, "1000"},
		{`"1e0000000000002"`, "100"},
		{`"0016"`, "16"},
		{`"1E+1"`, "10"},
		{`"\t16"`, "16"},
		{`"\u000b16"`, "16"},
		{`"5."`, "5"},
		{`"+5"`, "5"},
		{`10.5`, "21/2"},
		{`"1e2147483647"`, "1000"},
		{`"12345678901234567890e2147483647"`, "1000"},
		{`1e400`, "1000"},
		{`1e-400`, "0"},
		{`"null"`, "nil"},
		{`"   "`, "nil"},
		{`null`, "nil"},
		{`"1/2"`, "error"},
		{`"Infinity"`, "error"},
		{`"1_6"`, "error"},
		{`"16e"`, "error"},
		{`"."`, "error"},
		{`"5.e1"`, "error"},
		{`"١"`, "error"},
		{`"１６"`, "error"},
		{`"1e2147483648"`, "error"},
		{`"1e-2147483648"`, "error"},
		{`"0.1e-2147483647"`, "error"},
		{`"1e12345678901"`, "error"},
		{`"1e00000000002147483647"`, "1000"},
		{`true`, "error"},
		{`[16]`, "error"},
	}
	for _, c := range decimals {
		r, ok := readJavaDecimal(json.RawMessage(c.raw))
		got := describeRat(r)
		if !ok {
			got = "error"
		}
		if got != c.want {
			t.Errorf("文字の大きさの欄の %s を %s と読んだ、期待は %s", c.raw, got, c.want)
		}
	}
	strs := []struct{ raw, want string }{
		{`"null"`, "null"},
		{`-0`, "-0"},
		{`1E+2`, "1E+2"},
		{`1.0e+5`, "1.0e+5"},
		{`-0.0`, "-0.0"},
		{`true`, "true"},
		{`null`, "nil"},
		{`["pdf"]`, "error"},
		{`{}`, "error"},
	}
	for _, c := range strs {
		s, ok := readJavaString(json.RawMessage(c.raw))
		got := describeString(s)
		if !ok {
			got = "error"
		}
		if got != c.want {
			t.Errorf("文字列の欄の %s を %s と読んだ、Jackson は %s", c.raw, got, c.want)
		}
	}
}

// TestExportBody_NumberLength は、Jackson と同じく、数字が1000を超える数と、前後の空白を除いた長さが1000を超える数の欄の
// 文字列を、読めない値とすることを確かめる(要件1の受入基準1)。境の値は、JDK 21 で Jackson 3.1.7 を動かして確かめた。
func TestExportBody_NumberLength(t *testing.T) {
	zeros := strings.Repeat
	const okPDF = "pdf attachment NotoSansJP 16 21/2 19/2 12 hex=b4c7e7 rgb=nil"
	unknown := func(raw string) string { return strings.Replace(validExportPDFBody, `{`, `{"x":[{"y":`+raw+`}],`, 1) }
	title := func(raw string) string { return exportPDFBody(t, `"title":16`, `"title":`+raw) }
	red := func(raw string) string {
		return exportPDFBody(t, exportColorPart, `"tableHeaderColor":{"rgb":{"r":`+raw+`,"g":2,"b":3}}`)
	}
	const okTitle = "pdf attachment NotoSansJP 6 21/2 19/2 12 hex=b4c7e7 rgb=nil"
	const okRed = "pdf attachment NotoSansJP 16 21/2 19/2 12 hex=nil rgb=12,2,3"
	cases := []struct {
		name string
		body string
		want exportBodyWant
	}{
		{name: "知らない鍵の1000桁の整数", body: unknown("1" + zeros("0", 999)), want: exportBodyWant{request: okPDF}},
		{name: "知らない鍵の1001桁の整数", body: unknown("1" + zeros("0", 1000)), want: exportBodyWant{unreadable: true}},
		{name: "1000桁の小数", body: title("6." + zeros("0", 999)), want: exportBodyWant{request: okTitle}},
		{name: "指数を足して1001桁の小数", body: title("6." + zeros("0", 999) + "e1"), want: exportBodyWant{unreadable: true}},
		{name: "長さ1000の大きさの文字列", body: title(`"6.` + zeros("0", 998) + `"`), want: exportBodyWant{request: okTitle}},
		{name: "長さ1001の大きさの文字列", body: title(`"6.` + zeros("0", 999) + `"`), want: exportBodyWant{unreadable: true}},
		{name: "空白を除いて長さ999の大きさの文字列", body: title(`" 6.` + zeros("0", 997) + ` "`), want: exportBodyWant{request: okTitle}},
		{name: "長さ1000の整数の文字列", body: red(`"` + zeros("0", 998) + `12"`), want: exportBodyWant{request: okRed}},
		{name: "長さ1001の整数の文字列", body: red(`"` + zeros("0", 999) + `12"`), want: exportBodyWant{unreadable: true}},
		{name: "空白を除いて長さ1000の整数の文字列", body: red(`" ` + zeros("0", 998) + `12"`), want: exportBodyWant{request: okRed}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { checkExportBody(t, c.body, c.want) })
	}
}
