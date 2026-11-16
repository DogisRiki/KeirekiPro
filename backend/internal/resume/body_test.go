package resume

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"reflect"
	"strings"
	"testing"
	"unicode/utf8"
)

// bodyCase は、testdata/body.json と testdata/utf8.json の1つの本文と、Java 版の答えである。
type bodyCase struct {
	Name     string `json:"name"`
	Endpoint string `json:"endpoint"`
	Body     string `json:"body"`
	// BodyBase64 は、UTF-8 として誤ったバイトを含む本文のバイトを base64 にしたものである(utf8.json)。
	BodyBase64 string `json:"bodyBase64"`
	Status     int    `json:"status"`
	Response   struct {
		Message string              `json:"message"`
		Errors  map[string][]string `json:"errors"`
	} `json:"response"`
	// DB は、status が 201 のときに、Java 版がデータベースに書いた行である。表の名前ごとに、列の名前と値を持つ。
	DB map[string]map[string]any `json:"db"`
}

func (c bodyCase) bytes(t *testing.T) []byte {
	t.Helper()
	if c.BodyBase64 == "" {
		return []byte(c.Body)
	}
	b, err := base64.StdEncoding.DecodeString(c.BodyBase64)
	if err != nil {
		t.Fatalf("本文 %s の base64 が読めない: %v", c.Name, err)
	}
	return b
}

// 経路ごとの、要求の本文を送る先である。
const (
	endpointCreateResume  = "POST /api/resumes"
	endpointCreateCareer  = "POST /api/resumes/{resumeId}/careers"
	endpointCreateProject = "POST /api/resumes/{resumeId}/projects"
)

// bodyState は、1つの本文を読んだ結果の種類である。
type bodyState int

const (
	// bodyRead は、本文を読めたことである。
	bodyRead bodyState = iota
	// bodyUnreadable は、本文を読めないことである。Java 版は 400 と空の errors で断る。
	bodyUnreadable
	// bodyFailed は、Java 版が 500 で答えたことである。
	bodyFailed
)

// bodyResult は、1つの本文の答えである。Java 版の答えと Go 版の答えを、この形にそろえて比べる。
type bodyResult struct {
	state bodyState
	// view は、読めた本文の欄の値を、JSON の鍵ごとに持つ。Go 版は、すべての欄の値を持つ。
	// Java 版は、201 で答えたときに、データベースに書いた行から分かる欄の値を持つ。
	view map[string]any
	// errors は、Java 版が入力の検査で断ったときの、欄ごとの文言である。
	errors map[string][]string
}

func (r bodyResult) String() string {
	switch r.state {
	case bodyUnreadable:
		return "読めない"
	case bodyFailed:
		return "500 で答えた"
	}
	if r.errors != nil {
		b, _ := json.Marshal(r.errors)
		return "読めて入力の検査で断った " + string(b)
	}
	b, _ := json.Marshal(r.view)
	return "読めた " + string(b)
}

// requestView は、要求の型の値の欄を、JSON の鍵ごとに、Java 版のデータベースの行の値と同じ形の値にする。
// 値の無い欄は nil にする。年月はその月の1日の日付の文字列にする。
func requestView(t *testing.T, v any) map[string]any {
	t.Helper()
	out := map[string]any{}
	rv := reflect.ValueOf(v)
	rt := rv.Type()
	for i := range rt.NumField() {
		key, _, _ := strings.Cut(rt.Field(i).Tag.Get("json"), ",")
		switch f := rv.Field(i).Interface().(type) {
		case *string:
			out[key] = nil
			if f != nil {
				out[key] = *f
			}
		case *bool:
			out[key] = nil
			if f != nil {
				out[key] = *f
			}
		case jsonYearMonth:
			out[key] = nil
			if f.Present {
				out[key] = formatYearMonth(f.Value) + "-01"
			}
		case jsonDate:
			out[key] = nil
			if f.Present {
				out[key] = formatDate(f.Value)
			}
		case jsonResumeID:
			out[key] = nil
			if f.Present {
				out[key] = f.Value.String()
			}
		case []*string:
			out[key] = nil
			if f != nil {
				list := make([]any, len(f))
				for j, s := range f {
					if s != nil {
						list[j] = *s
					}
				}
				out[key] = list
			}
		default:
			t.Fatalf("%s の欄 %s の型 %T を扱えない", rt.Name(), key, f)
		}
	}
	return out
}

// decodeFor は、経路の要求の型で、本文を decodeBody で読む。
func decodeFor(t *testing.T, endpoint string, body []byte) bodyResult {
	t.Helper()
	var v any
	var err error
	switch endpoint {
	case endpointCreateResume:
		v, err = decodeBody[createResumeRequest](body)
	case endpointCreateCareer:
		v, err = decodeBody[careerRequest](body)
	case endpointCreateProject:
		v, err = decodeBody[projectRequest](body)
	default:
		t.Fatalf("経路 %s の要求の型が無い", endpoint)
	}
	if err != nil {
		if !errors.Is(err, errUnreadableBody) {
			t.Fatalf("decodeBody の誤り %v が errUnreadableBody を包んでいない", err)
		}
		return bodyResult{state: bodyUnreadable}
	}
	return bodyResult{state: bodyRead, view: requestView(t, v)}
}

// requestTypeOf は、経路の要求の型である。
func requestTypeOf(t *testing.T, endpoint string) reflect.Type {
	t.Helper()
	switch endpoint {
	case endpointCreateResume:
		return reflect.TypeFor[createResumeRequest]()
	case endpointCreateCareer:
		return reflect.TypeFor[careerRequest]()
	case endpointCreateProject:
		return reflect.TypeFor[projectRequest]()
	}
	t.Fatalf("経路 %s の要求の型が無い", endpoint)
	return nil
}

// snakeToCamel は、データベースの列の名前を、要求の本文の鍵の名前に直す。例: company_name は companyName になる。
func snakeToCamel(s string) string {
	parts := strings.Split(s, "_")
	for i := 1; i < len(parts); i++ {
		parts[i] = strings.ToUpper(parts[i][:1]) + parts[i][1:]
	}
	return strings.Join(parts, "")
}

// javaView は、Java 版がデータベースに書いた行を、要求の本文の鍵ごとの値にする。
// techColumns は、技術スタックの表の列の名前と、要求の本文の鍵の名前の対応である。
func javaView(t *testing.T, c bodyCase, techColumns map[string]string) map[string]any {
	t.Helper()
	out := map[string]any{}
	for table, row := range c.DB {
		for column, value := range row {
			var key string
			switch table {
			case "resumes":
				// 経歴書の姓と名は、経歴書の作成の要求に無い
				if column != "name" {
					continue
				}
				key = "resumeName"
			case "careers", "projects":
				key = snakeToCamel(column)
			case "project_tech_stacks":
				var ok bool
				if key, ok = techColumns[column]; !ok {
					t.Fatalf("本文 %s の技術スタックの列 %s の鍵が分からない", c.Name, column)
				}
			default:
				t.Fatalf("本文 %s の表 %s は、控えの形に無い", c.Name, table)
			}
			out[key] = value
		}
	}
	return out
}

// javaResult は、Java 版の答えを、bodyResult に直す。
func javaResult(t *testing.T, c bodyCase, techColumns map[string]string) bodyResult {
	t.Helper()
	switch {
	case c.Status == 201:
		return bodyResult{state: bodyRead, view: javaView(t, c, techColumns)}
	case c.Status == 500:
		return bodyResult{state: bodyFailed}
	case c.Status != 400 || c.Response.Message != MessageInvalidInput:
		t.Fatalf("本文 %s の Java 版の答え %d %q は、控えの形に無い", c.Name, c.Status, c.Response.Message)
	case len(c.Response.Errors) == 0:
		return bodyResult{state: bodyUnreadable}
	}
	return bodyResult{state: bodyRead, errors: c.Response.Errors}
}

func isBlank(v any) bool {
	s, ok := v.(string)
	return v == nil || ok && strings.TrimSpace(s) == ""
}

// javaErrorRules は、Java 版が入力の検査で断った文言ごとに、Java 版が本文から読んだ値の条件である。
// Go 版が読んだ値がこの条件に合えば、Go 版は Java 版と同じ値を読んだとみなす。key は文言の欄の鍵である。
var javaErrorRules = map[string]func(view map[string]any, key string) bool{
	MessageResumeNameRequired:   func(v map[string]any, k string) bool { return isBlank(v[k]) },
	MessageCompanyNameRequired:  func(v map[string]any, k string) bool { return isBlank(v[k]) },
	MessageCareerActiveRequired: func(v map[string]any, k string) bool { return v[k] == nil },
	MessageNotNull:              func(v map[string]any, k string) bool { return v[k] == nil },
	MessageEndDateRequired: func(v map[string]any, _ string) bool {
		return v["isActive"] == false && v["endDate"] == nil
	},
	MessageEndDateWhileOngoing: func(v map[string]any, _ string) bool {
		return v["isActive"] == true && v["endDate"] != nil
	},
	MessageEndDateBeforeStart: func(v map[string]any, _ string) bool {
		end, ok1 := v["endDate"].(string)
		start, ok2 := v["startDate"].(string)
		return ok1 && ok2 && end < start
	},
}

// sameBody は、Go 版の答えが Java 版の答えと同じかを返す。
func sameBody(t *testing.T, name string, goRes, javaRes bodyResult) bool {
	t.Helper()
	if goRes.state != javaRes.state {
		return false
	}
	if goRes.state != bodyRead {
		return true
	}
	for key, msgs := range javaRes.errors {
		for _, msg := range msgs {
			rule, ok := javaErrorRules[msg]
			if !ok {
				t.Fatalf("本文 %s の Java 版の文言 %q は、控えの形に無い", name, msg)
			}
			if !rule(goRes.view, key) {
				return false
			}
		}
	}
	for key, want := range javaRes.view {
		got, ok := goRes.view[key]
		if !ok {
			t.Fatalf("本文 %s の Java 版の欄 %s が、Go 版の要求の型に無い", name, key)
		}
		if !reflect.DeepEqual(got, want) {
			return false
		}
	}
	return true
}

// checkBodyAgainstJava は、1つの本文の Go 版の答えを、Java 版の答えとテストの中の表と照らす。
// screen は、画面が送る書き方の本文かどうかである。
func checkBodyAgainstJava(t *testing.T, name string, goRes, javaRes bodyResult, diffs map[string]string, screen bool) {
	t.Helper()
	id, inTable := diffs[name]
	if sameBody(t, name, goRes, javaRes) {
		if inTable {
			t.Errorf("本文 %s: Go 版の答えは Java 版と同じ %s なのに、表に %s がある", name, goRes, id)
		}
		return
	}
	if !inTable {
		t.Errorf("本文 %s: Go 版の答え %s が Java 版の答え %s と違うのに、表に無い", name, goRes, javaRes)
		return
	}
	if screen {
		t.Errorf("本文 %s は画面が送る書き方なのに、Go 版の答え %s が Java 版の答え %s と違う", name, goRes, javaRes)
	}
}

// screenValue は、要求の型の欄の型ごとに、画面がその欄に送る書き方の値かを返す。
func screenValue(ft reflect.Type, raw json.RawMessage) bool {
	s := string(raw)
	switch ft {
	case reflect.TypeFor[*string]():
		return strings.HasPrefix(s, `"`)
	case reflect.TypeFor[*bool]():
		return s == "true" || s == "false"
	case reflect.TypeFor[jsonYearMonth]():
		return screenYearMonth.MatchString(s)
	case reflect.TypeFor[jsonDate]():
		return screenDate.MatchString(s)
	case reflect.TypeFor[jsonResumeID]():
		var id string
		return s == "null" || json.Unmarshal(raw, &id) == nil && (id == "" || screenID.MatchString(id))
	case reflect.TypeFor[[]*string]():
		var list []json.RawMessage
		if json.Unmarshal(raw, &list) != nil || list == nil {
			return false
		}
		for _, e := range list {
			if !strings.HasPrefix(string(e), `"`) {
				return false
			}
		}
		return true
	}
	return false
}

// screenBody は、本文が、画面が送る書き方かを返す。画面は、UTF-8 として正しい本文に、要求の型の鍵の名前のとおりの鍵を
// 1つずつ書き、文字列の欄に文字列を、真偽の欄に true か false を、年月と日付の欄に入力欄の形の文字列か空の文字列か null を、
// 技術スタックの欄に文字列の並びを入れる。
func screenBody(body []byte, rt reflect.Type) bool {
	if !utf8.Valid(body) {
		return false
	}
	fields := map[string]reflect.Type{}
	for i := range rt.NumField() {
		key, _, _ := strings.Cut(rt.Field(i).Tag.Get("json"), ",")
		fields[key] = rt.Field(i).Type
	}
	dec := json.NewDecoder(bytes.NewReader(body))
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
		var raw json.RawMessage
		if err := dec.Decode(&raw); err != nil {
			return false
		}
		ft, ok := fields[key]
		if !ok || seen[key] || !screenValue(ft, raw) {
			return false
		}
		seen[key] = true
	}
	return true
}

// loadBodyJSON は、testdata/body.json の本文を読む。
func loadBodyJSON(t *testing.T) []bodyCase {
	t.Helper()
	b, err := os.ReadFile("testdata/body.json")
	return parseBodyCases(t, "testdata/body.json", b, err)
}

// loadUTF8JSON は、testdata/utf8.json の本文を読む。
func loadUTF8JSON(t *testing.T) []bodyCase {
	t.Helper()
	b, err := os.ReadFile("testdata/utf8.json")
	return parseBodyCases(t, "testdata/utf8.json", b, err)
}

// parseBodyCases は、正解のファイル file を読んだ結果から、本文を取り出す。
func parseBodyCases(t *testing.T, file string, b []byte, err error) []bodyCase {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
	var data struct {
		Cases []bodyCase `json:"cases"`
	}
	if err := json.Unmarshal(b, &data); err != nil {
		t.Fatal(err)
	}
	if len(data.Cases) == 0 {
		t.Fatalf("%s に本文が無い", file)
	}
	return data.Cases
}

// techStackColumnCount は、技術スタックの小分類の数である。
const techStackColumnCount = 35

// loadTechColumns は、技術スタックの表の列の名前と、要求の本文の鍵の名前の対応を、body.json の本文
// project-tech-all-lists から作る。この本文は、技術スタックの35の鍵のそれぞれに、鍵の名前を1つだけ入れた並びを送った。
func loadTechColumns(t *testing.T, cases []bodyCase) map[string]string {
	t.Helper()
	for _, c := range cases {
		if c.Name != "project-tech-all-lists" {
			continue
		}
		out := map[string]string{}
		for column, value := range c.DB["project_tech_stacks"] {
			list, ok := value.([]any)
			if !ok || len(list) != 1 {
				t.Fatalf("本文 %s の技術スタックの列 %s の値 %v が、鍵の名前1つの並びでない", c.Name, column, value)
			}
			out[column], _ = list[0].(string)
		}
		if len(out) != techStackColumnCount {
			t.Fatalf("技術スタックの列が %d 個で、%d 個でない", len(out), techStackColumnCount)
		}
		return out
	}
	t.Fatal("body.json に本文 project-tech-all-lists が無い")
	return nil
}

// bodyDiffs は、body.json の本文のうち、Go 版の答えが Java 版と違う本文と、違いを載せた一覧の番号である。
// Java 版は、文字列の欄の数と真偽を文字列として読み、真偽の欄の文字列と整数を真偽として読み、鍵の大文字と小文字を区別する(CB-054)。
var bodyDiffs = map[string]string{
	"career-companyName-string-int":              "CB-054",
	"career-companyName-string-decimal":          "CB-054",
	"career-companyName-string-negative-zero":    "CB-054",
	"career-companyName-string-exp":              "CB-054",
	"career-companyName-string-exp-upper":        "CB-054",
	"career-companyName-string-big-int":          "CB-054",
	"career-companyName-string-negative-decimal": "CB-054",
	"career-companyName-string-true":             "CB-054",
	"career-companyName-string-false":            "CB-054",
	"career-isActive-str-true":                   "CB-054",
	"career-isActive-str-True":                   "CB-054",
	"career-isActive-str-TRUE":                   "CB-054",
	"career-isActive-str-false":                  "CB-054",
	"career-isActive-str-False":                  "CB-054",
	"career-isActive-str-FALSE":                  "CB-054",
	"career-isActive-str-spaced-true":            "CB-054",
	"career-isActive-str-tab-true":               "CB-054",
	"career-isActive-str-empty":                  "CB-054",
	"career-isActive-str-blank":                  "CB-054",
	"career-isActive-str-null":                   "CB-054",
	"career-isActive-str-spaced-null":            "CB-054",
	"career-isActive-int-0":                      "CB-054",
	"career-isActive-int-neg0":                   "CB-054",
	"career-isActive-int-1":                      "CB-054",
	"career-isActive-int-2":                      "CB-054",
	"career-isActive-int-neg1":                   "CB-054",
	"career-isActive-int-big":                    "CB-054",
	"career-key-case-CompanyName":                "CB-054",
	"career-key-case-isactive":                   "CB-054",
	"project-phases-str-TRUE-int-0":              "CB-054",
	"project-phases-str-empty":                   "CB-054",
	"project-tech-frontendLanguages-mixed":       "CB-054",
	"resume-resumeName-int":                      "CB-054",
	"resume-resumeName-decimal":                  "CB-054",
	"resume-resumeName-true":                     "CB-054",
	"resume-key-case-ResumeName":                 "CB-054",
}

// TestDecodeBody_MatchesJava は、Java 版に送って testdata/body.json に控えたすべての本文で、
// 画面が送る書き方の本文から Java 版と同じ値を読み、Java 版と違う答えになる本文が、テストの中の表と合うことを確かめる。
func TestDecodeBody_MatchesJava(t *testing.T) {
	cases := loadBodyJSON(t)
	techColumns := loadTechColumns(t, cases)
	seen := map[string]bool{}
	screens := 0
	for _, c := range cases {
		seen[c.Name] = true
		body := c.bytes(t)
		screen := screenBody(body, requestTypeOf(t, c.Endpoint))
		if screen {
			screens++
		}
		checkBodyAgainstJava(t, c.Name, decodeFor(t, c.Endpoint, body), javaResult(t, c, techColumns), bodyDiffs, screen)
	}
	if screens == 0 {
		t.Error("正解のファイルに、画面が送る書き方の本文が無い")
	}
	for name := range bodyDiffs {
		if !seen[name] {
			t.Errorf("表の本文 %s が、正解のファイルに無い", name)
		}
	}
}

// resumeIDCase は、testdata/ids.json の、経歴書の作成の resumeId の1つの書き方と、Java 版の答えである。
type resumeIDCase struct {
	// Input は、resumeId に入れた JSON の値の書き方である。<absent> は鍵を入れなかった要求である。
	Input  string `json:"input"`
	Result struct {
		Status int    `json:"status"`
		ReadID string `json:"readId"`
		Body   struct {
			Message string              `json:"message"`
			Errors  map[string][]string `json:"errors"`
		} `json:"body"`
	} `json:"result"`
}

const (
	// resumeIDAbsent は、resumeId の鍵を入れなかった要求の書き方である。
	resumeIDAbsent = "<absent>"
	// resumeIDNoCopy は、Java 版が写さずに経歴書を作ったことを表す readId である。
	resumeIDNoCopy = "<no copy>"
)

// resumeIDDiffs は、経歴書の作成の resumeId の書き方のうち、Go 版の答えが Java 版と違う書き方と、違いを載せた一覧の番号である。
// Java 版は、前後の空白を除いて読み、空白だけの値を写さない作成にし、16バイトを base64 で書いた値も読む。
// Go 版は、uuid.Parse で読む(CB-052)。
var resumeIDDiffs = map[string]string{
	`"1b4e28ba-2fa1-11d2-883f-0016d3cca427 "`: "CB-052",
	`"  "`:                                            "CB-052",
	`"G04oui+hEdKIPwAW08ykJw=="`:                      "CB-052",
	`"G04oui+hEdKIPwAW08ykJw"`:                        "CB-052",
	`"+/v7+/v7+/v7+/v7+/v7+w=="`:                      "CB-052",
	`"-_v7-_v7-_v7-_v7-_v7-w=="`:                      "CB-052",
	`" G04oui+hEdKIPwAW08ykJw=="`:                     "CB-052",
	`"1b4e28ba2fa111d2883f0016d3cca427"`:              "CB-052",
	`"{1b4e28ba-2fa1-11d2-883f-0016d3cca427}"`:        "CB-052",
	`"urn:uuid:1b4e28ba-2fa1-11d2-883f-0016d3cca427"`: "CB-052",
}

// resumeIDResult は、resumeId の1つの書き方の答えである。
type resumeIDResult struct {
	state bodyState
	// id は、写す元の経歴書の ID である。写さない作成のときは resumeIDNoCopy にする。
	id string
}

func (r resumeIDResult) String() string {
	if r.state == bodyUnreadable {
		return "読めない"
	}
	return "読めた " + r.id
}

// TestDecodeBody_ResumeID は、Java 版に送って testdata/ids.json の resumeIds に控えた、経歴書の作成の resumeId の
// すべての書き方で、Java 版と違う答えになる書き方が、テストの中の表と合うことを確かめる。
func TestDecodeBody_ResumeID(t *testing.T) {
	b, err := os.ReadFile("testdata/ids.json")
	if err != nil {
		t.Fatal(err)
	}
	var data struct {
		ResumeIDs []resumeIDCase `json:"resumeIds"`
	}
	if err := json.Unmarshal(b, &data); err != nil {
		t.Fatal(err)
	}
	if len(data.ResumeIDs) == 0 {
		t.Fatal("控えの resumeId の書き方が無い")
	}
	seen := map[string]bool{}
	for _, c := range data.ResumeIDs {
		seen[c.Input] = true

		var javaRes resumeIDResult
		switch {
		case c.Result.Status == 201 && c.Result.ReadID != "":
			javaRes = resumeIDResult{state: bodyRead, id: c.Result.ReadID}
		case c.Result.Status == 400 && c.Result.Body.Message == MessageInvalidInput && len(c.Result.Body.Errors) == 0:
			javaRes = resumeIDResult{state: bodyUnreadable}
		default:
			t.Fatalf("書き方 %s の Java 版の答え %d は、控えの形に無い", c.Input, c.Result.Status)
		}

		body := `{"resumeName":"写し"}`
		if c.Input != resumeIDAbsent {
			body = `{"resumeName":"写し","resumeId":` + c.Input + `}`
		}
		var goRes resumeIDResult
		req, err := decodeBody[createResumeRequest]([]byte(body))
		switch {
		case err != nil:
			if !errors.Is(err, errUnreadableBody) {
				t.Fatalf("書き方 %s: decodeBody の誤り %v が errUnreadableBody を包んでいない", c.Input, err)
			}
			goRes = resumeIDResult{state: bodyUnreadable}
		case !req.ResumeID.Present:
			goRes = resumeIDResult{state: bodyRead, id: resumeIDNoCopy}
		default:
			goRes = resumeIDResult{state: bodyRead, id: req.ResumeID.Value.String()}
		}

		// 画面は、resumeId に、Java 版が答えに入れた小文字の形の ID か、空の文字列か null を入れるか、鍵を入れない
		screen := c.Input == resumeIDAbsent ||
			screenValue(reflect.TypeFor[jsonResumeID](), json.RawMessage(c.Input))
		id, inTable := resumeIDDiffs[c.Input]
		switch {
		case goRes == javaRes && inTable:
			t.Errorf("書き方 %s: Go 版の答えは Java 版と同じ %s なのに、表に %s がある", c.Input, goRes, id)
		case goRes != javaRes && !inTable:
			t.Errorf("書き方 %s: Go 版の答え %s が Java 版の答え %s と違うのに、表に無い", c.Input, goRes, javaRes)
		case goRes != javaRes && screen:
			t.Errorf("書き方 %s は画面が送る書き方なのに、Go 版の答え %s が Java 版の答え %s と違う", c.Input, goRes, javaRes)
		}
	}
	for input := range resumeIDDiffs {
		if !seen[input] {
			t.Errorf("表の書き方 %s が、正解のファイルに無い", input)
		}
	}
}

// utf8Diffs は、testdata/utf8.json の本文のうち、Go 版の答えが Java 版と違う本文と、違いを載せた一覧の番号である。
// Java 版は、UTF-8 として誤ったバイトの一部を断り、一部を対になっていないサロゲートとして受ける。Go 版は、誤ったバイトを
// 1バイトずつ U+FFFD に置き換えて読む(CB-055)。
var utf8Diffs = map[string]string{
	"career-companyName-ff":                            "CB-055",
	"career-companyName-end-ff":                        "CB-055",
	"project-frontendLanguages-ff":                     "CB-055",
	"career-companyName-fe":                            "CB-055",
	"career-companyName-end-fe":                        "CB-055",
	"project-frontendLanguages-fe":                     "CB-055",
	"career-companyName-c3-28":                         "CB-055",
	"career-companyName-end-c3-28":                     "CB-055",
	"project-frontendLanguages-c3-28":                  "CB-055",
	"career-companyName-a0-a1":                         "CB-055",
	"career-companyName-end-a0-a1":                     "CB-055",
	"project-frontendLanguages-a0-a1":                  "CB-055",
	"career-companyName-e2-28-a1":                      "CB-055",
	"career-companyName-end-e2-28-a1":                  "CB-055",
	"project-frontendLanguages-e2-28-a1":               "CB-055",
	"career-companyName-e2-82-28":                      "CB-055",
	"career-companyName-end-e2-82-28":                  "CB-055",
	"project-frontendLanguages-e2-82-28":               "CB-055",
	"career-companyName-f0-28-8c-bc":                   "CB-055",
	"career-companyName-end-f0-28-8c-bc":               "CB-055",
	"project-frontendLanguages-f0-28-8c-bc":            "CB-055",
	"career-companyName-overlong-c0-af":                "CB-055",
	"career-companyName-end-overlong-c0-af":            "CB-055",
	"project-frontendLanguages-overlong-c0-af":         "CB-055",
	"career-companyName-surrogate-ed-a0-80":            "CB-055",
	"career-companyName-end-surrogate-ed-a0-80":        "CB-055",
	"project-frontendLanguages-surrogate-ed-a0-80":     "CB-055",
	"career-companyName-above-max-f4-90-80-80":         "CB-055",
	"career-companyName-end-above-max-f4-90-80-80":     "CB-055",
	"project-frontendLanguages-above-max-f4-90-80-80":  "CB-055",
	"career-companyName-lone-continuation-80":          "CB-055",
	"career-companyName-end-lone-continuation-80":      "CB-055",
	"project-frontendLanguages-lone-continuation-80":   "CB-055",
	"career-companyName-truncated-e3-81":               "CB-055",
	"career-companyName-end-truncated-e3-81":           "CB-055",
	"project-frontendLanguages-truncated-e3-81":        "CB-055",
	"career-companyName-overlong-c1-bf":                "CB-055",
	"career-companyName-end-overlong-c1-bf":            "CB-055",
	"project-frontendLanguages-overlong-c1-bf":         "CB-055",
	"career-companyName-overlong-c0-80":                "CB-055",
	"career-companyName-end-overlong-c0-80":            "CB-055",
	"project-frontendLanguages-overlong-c0-80":         "CB-055",
	"career-companyName-overlong3-e0-80-af":            "CB-055",
	"career-companyName-end-overlong3-e0-80-af":        "CB-055",
	"project-frontendLanguages-overlong3-e0-80-af":     "CB-055",
	"career-companyName-overlong4-f0-80-80-af":         "CB-055",
	"career-companyName-end-overlong4-f0-80-80-af":     "CB-055",
	"project-frontendLanguages-overlong4-f0-80-80-af":  "CB-055",
	"career-companyName-low-surrogate-ed-bf-bf":        "CB-055",
	"career-companyName-end-low-surrogate-ed-bf-bf":    "CB-055",
	"project-frontendLanguages-low-surrogate-ed-bf-bf": "CB-055",
	"career-companyName-f5-80-80-80":                   "CB-055",
	"career-companyName-end-f5-80-80-80":               "CB-055",
	"project-frontendLanguages-f5-80-80-80":            "CB-055",
	"career-companyName-f7-bf-bf-bf":                   "CB-055",
	"career-companyName-end-f7-bf-bf-bf":               "CB-055",
	"project-frontendLanguages-f7-bf-bf-bf":            "CB-055",
	"career-companyName-f8-88-80-80-80":                "CB-055",
	"career-companyName-end-f8-88-80-80-80":            "CB-055",
	"project-frontendLanguages-f8-88-80-80-80":         "CB-055",
}

// rawStringValue は、本文の中の、鍵 key の文字列の値(並びのときは最初の要素)のバイトを、JSON の書き方のまま返す。
func rawStringValue(t *testing.T, name string, body []byte, key string) []byte {
	t.Helper()
	for _, prefix := range []string{`"` + key + `":"`, `"` + key + `":["`} {
		i := bytes.Index(body, []byte(prefix))
		if i < 0 {
			continue
		}
		rest := body[i+len(prefix):]
		j := bytes.IndexByte(rest, '"')
		if j < 0 || bytes.IndexByte(rest[:j], '\\') >= 0 {
			t.Fatalf("本文 %s の鍵 %s の値を、エスケープの無い文字列として取り出せない", name, key)
		}
		return rest[:j]
	}
	t.Fatalf("本文 %s に鍵 %s の文字列が無い", name, key)
	return nil
}

// TestDecodeBody_InvalidUTF8 は、Java 版に送って testdata/utf8.json に控えたすべての本文で、Go 版が、UTF-8 として
// 誤ったバイトを1バイトずつ U+FFFD に置き換えた値を読み、Java 版と違う答えになる本文が、テストの中の表と合うことを確かめる。
func TestDecodeBody_InvalidUTF8(t *testing.T) {
	techColumns := loadTechColumns(t, loadBodyJSON(t))
	cases := loadUTF8JSON(t)
	seen := map[string]bool{}
	for _, c := range cases {
		seen[c.Name] = true
		body := c.bytes(t)
		goRes := decodeFor(t, c.Endpoint, body)
		if goRes.state != bodyRead {
			t.Errorf("本文 %s を、Go 版は読めなかった", c.Name)
			continue
		}

		// 誤ったバイトを1バイトずつ U+FFFD に置き換えた値を、送った本文のバイトから作る
		var got any
		var raw []byte
		switch c.Endpoint {
		case endpointCreateCareer:
			got, raw = goRes.view["companyName"], rawStringValue(t, c.Name, body, "companyName")
		case endpointCreateProject:
			list, _ := goRes.view["frontendLanguages"].([]any)
			if len(list) != 1 {
				t.Errorf("本文 %s: Go 版が読んだ frontendLanguages %v の要素が1つでない", c.Name, list)
				continue
			}
			got, raw = list[0], rawStringValue(t, c.Name, body, "frontendLanguages")
		default:
			t.Fatalf("本文 %s の経路 %s は、控えの形に無い", c.Name, c.Endpoint)
		}
		var want strings.Builder
		for _, r := range string(raw) {
			want.WriteRune(r)
		}
		if got != want.String() {
			t.Errorf("本文 %s: Go 版が読んだ値 %q が、誤ったバイトを U+FFFD に置き換えた値 %q でない", c.Name, got, want.String())
		}
		// 送った本文は U+FFFD そのものを含まないので、置き換えた値が U+FFFD を含むのは、誤ったバイトを含む本文だけである。
		// これにより、置き換えた値を作る手順が、誤ったバイトを置き換えずに素通ししていないことを確かめる
		if utf8.ValidString(string(raw)) && strings.Contains(string(raw), "�") {
			t.Fatalf("本文 %s の値が U+FFFD そのものを含む", c.Name)
		}
		if strings.ContainsRune(want.String(), utf8.RuneError) == utf8.Valid(raw) {
			t.Errorf("本文 %s: UTF-8 として正しいかと、置き換えた値が U+FFFD を含むかが合わない", c.Name)
		}

		checkBodyAgainstJava(t, c.Name, goRes, javaResult(t, c, techColumns), utf8Diffs,
			screenBody(body, requestTypeOf(t, c.Endpoint)))
	}
	for name := range utf8Diffs {
		if !seen[name] {
			t.Errorf("表の本文 %s が、正解のファイルに無い", name)
		}
	}
}

// TestDecodeBody_DiffTableInChangedBehaviors は、本文の読み手のテストの中の表の番号が、変えた動きの一覧にあることを確かめる。
func TestDecodeBody_DiffTableInChangedBehaviors(t *testing.T) {
	t.Run("型の違う値を入れた本文", func(t *testing.T) { checkDiffTableInChangedBehaviors(t, bodyDiffs) })
	t.Run("経歴書の作成の resumeId", func(t *testing.T) { checkDiffTableInChangedBehaviors(t, resumeIDDiffs) })
	t.Run("UTF-8 として誤ったバイト", func(t *testing.T) { checkDiffTableInChangedBehaviors(t, utf8Diffs) })
}

// TestDecodeBody_WholeBody は、本文の全体が null のときに、すべての欄の値が無いことにし、本文の全体が並び、文字列、数、
// 真偽のときと、JSON として誤っているときに、errUnreadableBody を包んだ誤りを返すことを確かめる。
func TestDecodeBody_WholeBody(t *testing.T) {
	got, err := decodeBody[careerRequest]([]byte("null"))
	if err != nil {
		t.Fatalf("本文 null: 誤り %v を返した", err)
	}
	if !reflect.DeepEqual(got, careerRequest{}) {
		t.Errorf("本文 null: 値の無くない欄がある %+v", got)
	}
	for _, body := range []string{`[]`, `"a"`, `1`, `true`, ``, `{`, `{"companyName":"A"}x`} {
		got, err := decodeBody[careerRequest]([]byte(body))
		if !errors.Is(err, errUnreadableBody) {
			t.Errorf("本文 %q: 誤り %v が errUnreadableBody を包んでいない", body, err)
		}
		if !reflect.DeepEqual(got, careerRequest{}) {
			t.Errorf("本文 %q: 読めないのに、値のある欄を返した %+v", body, got)
		}
	}
}

// TestDecodeBody_LoneSurrogate は、対になっていないサロゲートの \uXXXX の書き方を、U+FFFD に置き換えて読むことを確かめる。
func TestDecodeBody_LoneSurrogate(t *testing.T) {
	tests := map[string]string{
		`{"companyName":"前\ud800後"}`:      "前�後",
		`{"companyName":"前\udc00後"}`:      "前�後",
		`{"companyName":"前\udc00\ud800"}`: "前��",
		`{"companyName":"前😀後"}`:           "前😀後",
	}
	for body, want := range tests {
		got, err := decodeBody[careerRequest]([]byte(body))
		if err != nil {
			t.Errorf("本文 %s: 誤り %v を返した", body, err)
			continue
		}
		if got.CompanyName == nil || *got.CompanyName != want {
			t.Errorf("本文 %s: 会社名 %v を読んだ。want %q", body, got.CompanyName, want)
		}
	}
}

// TestDecodeBody_RequestKeys は、8つの要求の型が、Java 版の要求の型と同じ名前の鍵を読むことを確かめる。
// 画面が送る書き方で、すべての鍵に値を入れた本文を読み、欄ごとの値を確かめる。
func TestDecodeBody_RequestKeys(t *testing.T) {
	tech := map[string]any{}
	techBody := ""
	for _, key := range []string{
		"frontendLanguages", "frontendFrameworks", "frontendLibraries", "frontendBuildTools", "frontendPackageManagers",
		"frontendLinters", "frontendFormatters", "frontendTestingTools",
		"backendLanguages", "backendFrameworks", "backendLibraries", "backendBuildTools", "backendPackageManagers",
		"backendLinters", "backendFormatters", "backendTestingTools", "ormTools", "auth",
		"clouds", "operatingSystems", "containers", "databases", "webServers", "ciCdTools", "iacTools",
		"monitoringTools", "loggingTools",
		"sourceControls", "projectManagements", "communicationTools", "documentationTools", "apiDevelopmentTools",
		"designTools", "editors", "developmentEnvironments",
	} {
		tech[key] = []any{key}
		techBody += fmt.Sprintf(`,%q:[%q]`, key, key)
	}
	if len(tech) != techStackColumnCount {
		t.Fatalf("技術スタックの鍵が %d 個で、%d 個でない", len(tech), techStackColumnCount)
	}
	project := map[string]any{
		"companyName": "A社", "startDate": "2020-01-01", "endDate": "2023-12-01", "isActive": false,
		"name": "案件", "overview": "概要", "teamComp": "5名", "role": "開発", "achievement": "成果",
		"requirements": true, "basicDesign": false, "detailedDesign": true, "implementation": false,
		"integrationTest": true, "systemTest": false, "maintenance": true,
	}
	for k, v := range tech {
		project[k] = v
	}

	tests := []struct {
		name string
		body string
		got  func([]byte) (any, error)
		want map[string]any
	}{
		{
			"経歴書の作成",
			`{"resumeName":"経歴書","resumeId":"1b4e28ba-2fa1-11d2-883f-0016d3cca427"}`,
			func(b []byte) (any, error) { return decodeBody[createResumeRequest](b) },
			map[string]any{"resumeName": "経歴書", "resumeId": "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
		},
		{
			"基本の情報の更新",
			`{"resumeName":"経歴書","date":"2024-01-15","lastName":"山田","firstName":"太郎"}`,
			func(b []byte) (any, error) { return decodeBody[updateResumeBasicRequest](b) },
			map[string]any{"resumeName": "経歴書", "date": "2024-01-15", "lastName": "山田", "firstName": "太郎"},
		},
		{
			"職歴",
			`{"companyName":"A社","startDate":"2020-01","endDate":"2023-12","isActive":false}`,
			func(b []byte) (any, error) { return decodeBody[careerRequest](b) },
			map[string]any{"companyName": "A社", "startDate": "2020-01-01", "endDate": "2023-12-01", "isActive": false},
		},
		{
			"プロジェクト",
			`{"companyName":"A社","startDate":"2020-01","endDate":"2023-12","isActive":false,"name":"案件","overview":"概要",` +
				`"teamComp":"5名","role":"開発","achievement":"成果","requirements":true,"basicDesign":false,` +
				`"detailedDesign":true,"implementation":false,"integrationTest":true,"systemTest":false,"maintenance":true` +
				techBody + `}`,
			func(b []byte) (any, error) { return decodeBody[projectRequest](b) },
			project,
		},
		{
			"資格",
			`{"name":"基本情報技術者","date":"2021-04"}`,
			func(b []byte) (any, error) { return decodeBody[certificationRequest](b) },
			map[string]any{"name": "基本情報技術者", "date": "2021-04-01"},
		},
		{
			"ポートフォリオ",
			`{"name":"作品","overview":"概要","techStack":"Go","link":"https://example.com"}`,
			func(b []byte) (any, error) { return decodeBody[portfolioRequest](b) },
			map[string]any{"name": "作品", "overview": "概要", "techStack": "Go", "link": "https://example.com"},
		},
		{
			"SNS",
			`{"name":"GitHub","link":"https://github.com/example"}`,
			func(b []byte) (any, error) { return decodeBody[snsPlatformRequest](b) },
			map[string]any{"name": "GitHub", "link": "https://github.com/example"},
		},
		{
			"自己PR",
			`{"title":"題","content":"内容"}`,
			func(b []byte) (any, error) { return decodeBody[selfPromotionRequest](b) },
			map[string]any{"title": "題", "content": "内容"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			v, err := tt.got([]byte(tt.body))
			if err != nil {
				t.Fatalf("誤り %v を返した", err)
			}
			if !screenBody([]byte(tt.body), reflect.TypeOf(v)) {
				t.Errorf("本文 %s が、画面が送る書き方でない", tt.body)
			}
			if got := requestView(t, v); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("読んだ値\n got  %v\n want %v", got, tt.want)
			}
		})
	}
}
