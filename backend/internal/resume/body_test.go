package resume

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"strings"
	"testing"
	"unicode/utf8"
)

// 経路ごとの、要求の本文を送る先である。
const (
	endpointCreateResume  = "POST /api/resumes"
	endpointCreateCareer  = "POST /api/resumes/{resumeId}/careers"
	endpointCreateProject = "POST /api/resumes/{resumeId}/projects"
)

// requestView は、要求の型の値の欄を、JSON の鍵ごとの値にする。
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

// decodeFor は、経路の要求の型で、本文を decodeBody で読み、欄の値を requestView の形で返す。読めない本文では nil を返す。
func decodeFor(t *testing.T, endpoint string, body []byte) map[string]any {
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
		return nil
	}
	return requestView(t, v)
}

// presentFields は、requestView の形の値のうち、値のある欄だけを残す。
func presentFields(view map[string]any) map[string]any {
	out := map[string]any{}
	for k, v := range view {
		if v != nil {
			out[k] = v
		}
	}
	return out
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

// techStackColumnCount は、技術スタックの小分類の数である。
const techStackColumnCount = 35

// projectBase は、プロジェクトの本文の、工程の systemTest と maintenance より前の欄である。
const projectBase = `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":true,"name":"案件","overview":"概要",` +
	`"teamComp":"5名","role":"開発","achievement":"成果","requirements":true,"basicDesign":true,"detailedDesign":false,` +
	`"implementation":true,"integrationTest":false`

// projectWant は、projectBase の欄を読んだ値に、extra の欄を重ねた答えを JSON で返す。extra の null の欄は、値の無い欄にする。
func projectWant(extra string) string {
	want := map[string]any{
		"companyName": "A社", "startDate": "2020-01-01", "isActive": true, "name": "案件", "overview": "概要",
		"teamComp": "5名", "role": "開発", "achievement": "成果", "requirements": true, "basicDesign": true,
		"detailedDesign": false, "implementation": true, "integrationTest": false,
	}
	var over map[string]any
	if err := json.Unmarshal([]byte(extra), &over); err != nil {
		panic(fmt.Sprintf("projectWant の %s が JSON でない: %v", extra, err))
	}
	for k, v := range over {
		if v == nil {
			delete(want, k)
			continue
		}
		want[k] = v
	}
	b, err := json.Marshal(want)
	if err != nil {
		panic(err)
	}
	return string(b)
}

// bodyTests は、要求の本文と、decodeBody が読んだ値のある欄である。読めない本文の want は "" である。
// cb は、Java 版と答えが違い、変えた動きの一覧に載せた番号である。
// Go 版は、encoding/json の読み方のとおりに、鍵の名前の大文字と小文字を区別せずに読み、文字列の欄の数と真偽を断り(CB-054)、
// 同じ鍵が2つあれば後ろの値を読み、知らない鍵を読み飛ばす。
var bodyTests = []struct {
	name, cb, endpoint, body, want string
}{
	{"career-companyName-string-int", "CB-054", endpointCreateCareer, `{"companyName":1,"startDate":"2020-01","endDate":null,"isActive":true}`, ""},
	{"career-companyName-string-decimal", "CB-054", endpointCreateCareer, `{"companyName":1.50,"startDate":"2020-01","endDate":null,"isActive":true}`, ""},
	{"career-companyName-string-negative-zero", "CB-054", endpointCreateCareer, `{"companyName":-0,"startDate":"2020-01","endDate":null,"isActive":true}`, ""},
	{"career-companyName-string-exp", "CB-054", endpointCreateCareer, `{"companyName":1e3,"startDate":"2020-01","endDate":null,"isActive":true}`, ""},
	{"career-companyName-string-exp-upper", "CB-054", endpointCreateCareer, `{"companyName":1E+3,"startDate":"2020-01","endDate":null,"isActive":true}`, ""},
	{"career-companyName-string-big-int", "CB-054", endpointCreateCareer, `{"companyName":12345678901234567890,"startDate":"2020-01","endDate":null,"isActive":true}`, ""},
	{"career-companyName-string-negative-decimal", "CB-054", endpointCreateCareer, `{"companyName":-1.0,"startDate":"2020-01","endDate":null,"isActive":true}`, ""},
	{"career-companyName-string-true", "CB-054", endpointCreateCareer, `{"companyName":true,"startDate":"2020-01","endDate":null,"isActive":true}`, ""},
	{"career-companyName-string-false", "CB-054", endpointCreateCareer, `{"companyName":false,"startDate":"2020-01","endDate":null,"isActive":true}`, ""},
	{"career-companyName-string-null", "", endpointCreateCareer, `{"companyName":null,"startDate":"2020-01","endDate":null,"isActive":true}`, `{"isActive":true,"startDate":"2020-01-01"}`},
	{"career-companyName-string-empty-array", "", endpointCreateCareer, `{"companyName":[],"startDate":"2020-01","endDate":null,"isActive":true}`, ""},
	{"career-companyName-string-array", "", endpointCreateCareer, `{"companyName":["a"],"startDate":"2020-01","endDate":null,"isActive":true}`, ""},
	{"career-companyName-string-object", "", endpointCreateCareer, `{"companyName":{},"startDate":"2020-01","endDate":null,"isActive":true}`, ""},
	{"career-companyName-string-spaces-kept", "", endpointCreateCareer, `{"companyName":"  前後の空白  ","startDate":"2020-01","endDate":null,"isActive":true}`, `{"companyName":"  前後の空白  ","isActive":true,"startDate":"2020-01-01"}`},
	{"career-companyName-string-ideographic-spaces", "", endpointCreateCareer, "{\"companyName\":\"\u3000全角\u3000\",\"startDate\":\"2020-01\",\"endDate\":null,\"isActive\":true}", "{\"companyName\":\"\u3000全角\u3000\",\"isActive\":true,\"startDate\":\"2020-01-01\"}"},
	{"career-companyName-string-escapes", "", endpointCreateCareer, `{"companyName":"a\"b\\c\/dé😀","startDate":"2020-01","endDate":null,"isActive":true}`, `{"companyName":"a\"b\\c/dé😀","isActive":true,"startDate":"2020-01-01"}`},
	{"career-companyName-absent", "", endpointCreateCareer, `{"startDate":"2020-01","endDate":null,"isActive":true}`, `{"isActive":true,"startDate":"2020-01-01"}`},
	{"career-isActive-true", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":true}`, `{"companyName":"A社","isActive":true,"startDate":"2020-01-01"}`},
	{"career-isActive-false", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":false}`, `{"companyName":"A社","isActive":false,"startDate":"2020-01-01"}`},
	{"career-isActive-str-true", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"true"}`, ""},
	{"career-isActive-str-True", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"True"}`, ""},
	{"career-isActive-str-TRUE", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"TRUE"}`, ""},
	{"career-isActive-str-false", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"false"}`, ""},
	{"career-isActive-str-False", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"False"}`, ""},
	{"career-isActive-str-FALSE", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"FALSE"}`, ""},
	{"career-isActive-str-spaced-true", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":" true "}`, ""},
	{"career-isActive-str-tab-true", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"\ttrue\n"}`, ""},
	{"career-isActive-str-ideographic-true", "", endpointCreateCareer, "{\"companyName\":\"A社\",\"startDate\":\"2020-01\",\"endDate\":null,\"isActive\":\"\u3000true\"}", ""},
	{"career-isActive-str-empty", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":""}`, ""},
	{"career-isActive-str-blank", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"  "}`, ""},
	{"career-isActive-str-null", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"null"}`, ""},
	{"career-isActive-str-spaced-null", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":" null "}`, ""},
	{"career-isActive-str-NULL", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"NULL"}`, ""},
	{"career-isActive-str-tRuE", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"tRuE"}`, ""},
	{"career-isActive-str-yes", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"yes"}`, ""},
	{"career-isActive-str-1", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"1"}`, ""},
	{"career-isActive-str-0", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"0"}`, ""},
	{"career-isActive-str-t", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":"t"}`, ""},
	{"career-isActive-int-0", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":0}`, ""},
	{"career-isActive-int-neg0", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":-0}`, ""},
	{"career-isActive-int-1", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":1}`, ""},
	{"career-isActive-int-2", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":2}`, ""},
	{"career-isActive-int-neg1", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":-1}`, ""},
	{"career-isActive-int-big", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":12345678901234567890}`, ""},
	{"career-isActive-dec-1.0", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":1.0}`, ""},
	{"career-isActive-dec-0.0", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":0.0}`, ""},
	{"career-isActive-exp-1e2", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":1e2}`, ""},
	{"career-isActive-array", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":[]}`, ""},
	{"career-isActive-array-true", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":[true]}`, ""},
	{"career-isActive-object", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":{}}`, ""},
	{"career-isActive-null", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":null}`, `{"companyName":"A社","startDate":"2020-01-01"}`},
	{"career-isActive-absent", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null}`, `{"companyName":"A社","startDate":"2020-01-01"}`},
	{"career-key-case-CompanyName", "CB-054", endpointCreateCareer, `{"CompanyName":"A社","startDate":"2020-01","endDate":null,"isActive":true}`, `{"companyName":"A社","isActive":true,"startDate":"2020-01-01"}`},
	{"career-key-case-isactive", "CB-054", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isactive":true}`, `{"companyName":"A社","isActive":true,"startDate":"2020-01-01"}`},
	{"career-key-unknown", "", endpointCreateCareer, `{"companyName":"A社","foo":{"x":[1,2]},"startDate":"2020-01","endDate":null,"isActive":true}`, `{"companyName":"A社","isActive":true,"startDate":"2020-01-01"}`},
	{"career-key-active-ignored", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":true,"active":false}`, `{"companyName":"A社","isActive":true,"startDate":"2020-01-01"}`},
	{"career-key-active-only", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"active":true}`, `{"companyName":"A社","startDate":"2020-01-01"}`},
	{"career-key-duplicate-string", "", endpointCreateCareer, `{"companyName":"前","companyName":"後","startDate":"2020-01","endDate":null,"isActive":true}`, `{"companyName":"後","isActive":true,"startDate":"2020-01-01"}`},
	{"career-key-duplicate-bool", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":"2023-12","isActive":true,"isActive":false}`, `{"companyName":"A社","endDate":"2023-12-01","isActive":false,"startDate":"2020-01-01"}`},
	{"career-key-duplicate-invalid-then-valid", "", endpointCreateCareer, `{"companyName":[],"companyName":"後","startDate":"2020-01","endDate":null,"isActive":true}`, ""},
	{"career-period-active-with-end", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":"2023-12","isActive":true}`, `{"companyName":"A社","endDate":"2023-12-01","isActive":true,"startDate":"2020-01-01"}`},
	{"career-period-inactive-no-end", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":false}`, `{"companyName":"A社","isActive":false,"startDate":"2020-01-01"}`},
	{"career-period-end-before-start", "", endpointCreateCareer, `{"companyName":"A社","startDate":"2020-01","endDate":"2019-12","isActive":false}`, `{"companyName":"A社","endDate":"2019-12-01","isActive":false,"startDate":"2020-01-01"}`},
	{"project-phases-systemTest-true-maintenance-false", "", endpointCreateProject, projectBase + `,"systemTest":true,"maintenance":false,"frontendLanguages":["Go"]}`, projectWant(`{"frontendLanguages":["Go"],"maintenance":false,"systemTest":true}`)},
	{"project-phases-systemTest-false-maintenance-true", "", endpointCreateProject, projectBase + `,"systemTest":false,"maintenance":true}`, projectWant(`{"maintenance":true,"systemTest":false}`)},
	{"project-phases-systemTest-absent", "", endpointCreateProject, projectBase + `,"maintenance":false}`, projectWant(`{"maintenance":false}`)},
	{"project-phases-systemTest-null", "", endpointCreateProject, projectBase + `,"systemTest":null,"maintenance":false}`, projectWant(`{"maintenance":false}`)},
	{"project-phases-two-null", "", endpointCreateProject, projectBase + `,"systemTest":null,"maintenance":null}`, projectWant(`{}`)},
	{"project-phases-str-TRUE-int-0", "CB-054", endpointCreateProject, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":true,"name":"案件","overview":"概要","teamComp":"5名","role":"開発","achievement":"成果","requirements":"TRUE","basicDesign":0,"detailedDesign":false,"implementation":true,"integrationTest":false,"systemTest":true,"maintenance":false}`, ""},
	{"project-phases-decimal", "", endpointCreateProject, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":true,"name":"案件","overview":"概要","teamComp":"5名","role":"開発","achievement":"成果","requirements":1.0,"basicDesign":true,"detailedDesign":false,"implementation":true,"integrationTest":false,"systemTest":true,"maintenance":false}`, ""},
	{"project-phases-str-empty", "CB-054", endpointCreateProject, `{"companyName":"A社","startDate":"2020-01","endDate":null,"isActive":true,"name":"案件","overview":"概要","teamComp":"5名","role":"開発","achievement":"成果","requirements":"","basicDesign":true,"detailedDesign":false,"implementation":true,"integrationTest":false,"systemTest":true,"maintenance":false}`, ""},
	{"project-tech-frontendLanguages-mixed", "CB-054", endpointCreateProject, projectBase + `,"systemTest":true,"maintenance":false,"frontendLanguages":["Go",1,1.50,-0,true,false,null,"a,b","\"q\"","\\","{x}"," sp ","","NULL","null"]}`, ""},
	{"project-tech-frontendLanguages-null", "", endpointCreateProject, projectBase + `,"systemTest":true,"maintenance":false,"frontendLanguages":null}`, projectWant(`{"maintenance":false,"systemTest":true}`)},
	{"project-tech-frontendLanguages-empty", "", endpointCreateProject, projectBase + `,"systemTest":true,"maintenance":false,"frontendLanguages":[]}`, projectWant(`{"frontendLanguages":[],"maintenance":false,"systemTest":true}`)},
	{"project-tech-frontendLanguages-string", "", endpointCreateProject, projectBase + `,"systemTest":true,"maintenance":false,"frontendLanguages":"Go"}`, ""},
	{"project-tech-frontendLanguages-object", "", endpointCreateProject, projectBase + `,"systemTest":true,"maintenance":false,"frontendLanguages":{}}`, ""},
	{"project-tech-frontendLanguages-number", "", endpointCreateProject, projectBase + `,"systemTest":true,"maintenance":false,"frontendLanguages":1}`, ""},
	{"project-tech-frontendLanguages-bool", "", endpointCreateProject, projectBase + `,"systemTest":true,"maintenance":false,"frontendLanguages":true}`, ""},
	{"project-tech-frontendLanguages-nested-array", "", endpointCreateProject, projectBase + `,"systemTest":true,"maintenance":false,"frontendLanguages":[[]]}`, ""},
	{"project-tech-frontendLanguages-nested-object", "", endpointCreateProject, projectBase + `,"systemTest":true,"maintenance":false,"frontendLanguages":[{}]}`, ""},
	{"project-tech-absent", "", endpointCreateProject, projectBase + `,"systemTest":true,"maintenance":false}`, projectWant(`{"maintenance":false,"systemTest":true}`)},
	{"resume-resumeName-int", "CB-054", endpointCreateResume, `{"resumeName":1}`, ""},
	{"resume-resumeName-decimal", "CB-054", endpointCreateResume, `{"resumeName":1.50}`, ""},
	{"resume-resumeName-true", "CB-054", endpointCreateResume, `{"resumeName":true}`, ""},
	{"resume-resumeName-null", "", endpointCreateResume, `{"resumeName":null}`, `{}`},
	{"resume-resumeName-array", "", endpointCreateResume, `{"resumeName":[]}`, ""},
	{"resume-resumeName-object", "", endpointCreateResume, `{"resumeName":{}}`, ""},
	{"resume-resumeName-spaces", "", endpointCreateResume, `{"resumeName":"  前後  "}`, `{"resumeName":"  前後  "}`},
	{"resume-resumeName-absent", "", endpointCreateResume, `{}`, `{}`},
	{"resume-key-case-ResumeName", "CB-054", endpointCreateResume, `{"ResumeName":"大文字"}`, `{"resumeName":"大文字"}`},
	{"resume-key-unknown", "", endpointCreateResume, `{"resumeName":"知らない鍵","foo":1}`, `{"resumeName":"知らない鍵"}`},
	{"resume-key-duplicate", "", endpointCreateResume, `{"resumeName":"前","resumeName":"後"}`, `{"resumeName":"後"}`},
}

// TestDecodeBody は、表の本文を decodeBody で読んだ答えが表の答えと同じになることと、
// Java 版と答えが違う本文が、画面が送る書き方でないことを確かめる。
func TestDecodeBody(t *testing.T) {
	screens := 0
	for _, tt := range bodyTests {
		t.Run(tt.name, func(t *testing.T) {
			view := decodeFor(t, tt.endpoint, []byte(tt.body))
			switch {
			case view == nil && tt.want != "":
				t.Errorf("本文 %s を読めなかった。want %s", tt.body, tt.want)
			case view != nil && tt.want == "":
				t.Errorf("本文 %s を読んだ %v。want 読めない", tt.body, presentFields(view))
			case view != nil:
				var want map[string]any
				if err := json.Unmarshal([]byte(tt.want), &want); err != nil {
					t.Fatalf("表の答え %s が JSON でない: %v", tt.want, err)
				}
				// 読んだ値を JSON にしてから読み直し、表の答えと同じ型の値にして比べる
				b, err := json.Marshal(presentFields(view))
				if err != nil {
					t.Fatal(err)
				}
				var got map[string]any
				if err := json.Unmarshal(b, &got); err != nil {
					t.Fatal(err)
				}
				if !reflect.DeepEqual(got, want) {
					t.Errorf("本文 %s の読んだ値\n got  %s\n want %s", tt.body, b, tt.want)
				}
			}
			screen := screenBody([]byte(tt.body), requestTypeOf(t, tt.endpoint))
			if screen {
				screens++
			}
			if tt.cb != "" && screen {
				t.Errorf("本文 %s は画面が送る書き方なのに、%s がある", tt.body, tt.cb)
			}
		})
	}
	// 画面が送る書き方の本文が無いと、上の screenBody の検査が何も確かめないことになる
	if screens == 0 {
		t.Error("表に、画面が送る書き方の本文が無い")
	}
}

// utf8Tests は、UTF-8 として誤ったバイトの並びと、正しい並びと、decodeBody がその並びを読んだ文字列である。
// Go 版は、encoding/json の読み方のとおりに、誤ったバイトを、UTF-8 として読めない区切りごとに U+FFFD に置き換えて読む。
// Java 版は、誤ったバイトの一部を断り、一部を対になっていないサロゲートとして受けた(CB-055)。
var utf8Tests = []struct {
	name string
	b    []byte
	repl string
	cb   string
}{
	{"ff", []byte{0xff}, "�", "CB-055"},
	{"fe", []byte{0xfe}, "�", "CB-055"},
	{"c3-28", []byte{0xc3, 0x28}, "�(", "CB-055"},
	{"a0-a1", []byte{0xa0, 0xa1}, "��", "CB-055"},
	{"e2-28-a1", []byte{0xe2, 0x28, 0xa1}, "�(�", "CB-055"},
	{"e2-82-28", []byte{0xe2, 0x82, 0x28}, "��(", "CB-055"},
	{"f0-28-8c-bc", []byte{0xf0, 0x28, 0x8c, 0xbc}, "�(��", "CB-055"},
	{"overlong-c0-af", []byte{0xc0, 0xaf}, strings.Repeat("�", 2), "CB-055"},
	{"surrogate-ed-a0-80", []byte{0xed, 0xa0, 0x80}, strings.Repeat("�", 3), "CB-055"},
	{"above-max-f4-90-80-80", []byte{0xf4, 0x90, 0x80, 0x80}, strings.Repeat("�", 4), "CB-055"},
	{"lone-continuation-80", []byte{0x80}, "�", "CB-055"},
	{"truncated-e3-81", []byte{0xe3, 0x81}, strings.Repeat("�", 2), "CB-055"},
	{"overlong-c1-bf", []byte{0xc1, 0xbf}, strings.Repeat("�", 2), "CB-055"},
	{"overlong-c0-80", []byte{0xc0, 0x80}, strings.Repeat("�", 2), "CB-055"},
	{"overlong3-e0-80-af", []byte{0xe0, 0x80, 0xaf}, strings.Repeat("�", 3), "CB-055"},
	{"overlong4-f0-80-80-af", []byte{0xf0, 0x80, 0x80, 0xaf}, strings.Repeat("�", 4), "CB-055"},
	{"low-surrogate-ed-bf-bf", []byte{0xed, 0xbf, 0xbf}, strings.Repeat("�", 3), "CB-055"},
	{"f5-80-80-80", []byte{0xf5, 0x80, 0x80, 0x80}, strings.Repeat("�", 4), "CB-055"},
	{"f7-bf-bf-bf", []byte{0xf7, 0xbf, 0xbf, 0xbf}, strings.Repeat("�", 4), "CB-055"},
	{"f8-88-80-80-80", []byte{0xf8, 0x88, 0x80, 0x80, 0x80}, strings.Repeat("�", 5), "CB-055"},
	// UTF-8 として正しい並びは、そのまま読む
	{"max-f4-8f-bf-bf", []byte{0xf4, 0x8f, 0xbf, 0xbf}, "\U0010FFFF", ""},
	{"emoji-f0-9f-98-80", []byte{0xf0, 0x9f, 0x98, 0x80}, "😀", ""},
	{"ef-bf-bf", []byte{0xef, 0xbf, 0xbf}, "￿", ""},
	{"e0-a0-80", []byte{0xe0, 0xa0, 0x80}, "ࠀ", ""},
}

// utf8Body は、本文の書き方 format の %s を、バイトの並び b に置き換えた本文である。
func utf8Body(format string, b []byte) []byte {
	before, after, _ := strings.Cut(format, "%s")
	return append(append([]byte(before), b...), after...)
}

// TestDecodeBody_InvalidUTF8 は、職歴の会社名とプロジェクトの技術スタックに、表のバイトの並びを入れた本文を、
// decodeBody が、表の文字列に置き換えて読むことと、Java 版と答えが違う本文が、画面が送る書き方でないことを確かめる。
func TestDecodeBody_InvalidUTF8(t *testing.T) {
	careerTail := `","startDate":"2020-01","endDate":null,"isActive":true}`
	forms := []struct {
		name, endpoint, format string
		// value は、読んだ値から、バイトの並びを入れた欄の値を取り出す。
		value func(view map[string]any) any
		want  func(repl string) any
	}{
		{
			"会社名の途中", endpointCreateCareer, `{"companyName":"前%s後` + careerTail,
			func(view map[string]any) any { return view["companyName"] },
			func(repl string) any { return "前" + repl + "後" },
		},
		{
			"会社名の終わり", endpointCreateCareer, `{"companyName":"前%s` + careerTail,
			func(view map[string]any) any { return view["companyName"] },
			func(repl string) any { return "前" + repl },
		},
		{
			"技術スタック", endpointCreateProject,
			projectBase + `,"systemTest":true,"maintenance":false,"frontendLanguages":["前%s後"]}`,
			func(view map[string]any) any { return view["frontendLanguages"] },
			func(repl string) any { return []any{"前" + repl + "後"} },
		},
	}
	for _, tt := range utf8Tests {
		for _, f := range forms {
			t.Run(tt.name+"/"+f.name, func(t *testing.T) {
				body := utf8Body(f.format, tt.b)
				view := decodeFor(t, f.endpoint, body)
				if view == nil {
					t.Fatalf("本文 %q を読めなかった", body)
				}
				if got, want := f.value(view), f.want(tt.repl); !reflect.DeepEqual(got, want) {
					t.Errorf("本文 %q: 読んだ値 %q, want %q", body, got, want)
				}
				if tt.cb != "" && screenBody(body, requestTypeOf(t, f.endpoint)) {
					t.Errorf("本文 %q は画面が送る書き方なのに、%s がある", body, tt.cb)
				}
			})
		}
		// 誤った並びだけに番号を付け、正しい並びには付けない
		if (tt.cb != "") == utf8.Valid(tt.b) {
			t.Errorf("並び %s: UTF-8 として正しいかと、番号 %q が合わない", tt.name, tt.cb)
		}
	}
}

const (
	// resumeIDAbsent は、resumeId の鍵を入れなかった要求の書き方である。
	resumeIDAbsent = "<absent>"
	// resumeIDNoCopy は、写さずに経歴書を作ることを表す答えである。
	resumeIDNoCopy = "<no copy>"
	// resumeIDUnreadable は、本文を読めないことを表す答えである。
	resumeIDUnreadable = "読めない"
)

// resumeIDTests は、経歴書の作成の resumeId の書き方と、写す元の経歴書の ID である。
// Go 版は、文字列を uuid.Parse で読み、空の文字列と null と鍵の無い要求を、写さない作成にする。
// Java 版は、前後の空白を除いて読み、空白だけの値を写さない作成にし、16バイトを base64 で書いた値も読んだ(CB-052)。
var resumeIDTests = []struct {
	cb, input, want string
}{
	{"", `"1b4e28ba-2fa1-11d2-883f-0016d3cca427"`, "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	{"", `"1B4E28BA-2FA1-11D2-883F-0016D3CCA427"`, "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	{"", `"1B4E28ba-2FA1-11d2-883F-0016D3CCA427"`, "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	// uuid.Parse は、38字の形の最初と最後の1字を確かめずに外すので、前後に1つずつ空白を付けた値も読む
	{"", `" 1b4e28ba-2fa1-11d2-883f-0016d3cca427 "`, "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	{"CB-052", `"1b4e28ba-2fa1-11d2-883f-0016d3cca427 "`, resumeIDUnreadable},
	{"", `""`, resumeIDNoCopy},
	{"CB-052", `"  "`, resumeIDUnreadable},
	{"", `null`, resumeIDNoCopy},
	{"", `"null"`, resumeIDUnreadable},
	{"", `"1-2-3-4-5"`, resumeIDUnreadable},
	{"CB-052", `"G04oui+hEdKIPwAW08ykJw=="`, resumeIDUnreadable},
	{"CB-052", `"G04oui+hEdKIPwAW08ykJw"`, resumeIDUnreadable},
	{"CB-052", `"+/v7+/v7+/v7+/v7+/v7+w=="`, resumeIDUnreadable},
	{"CB-052", `"-_v7-_v7-_v7-_v7-_v7-w=="`, resumeIDUnreadable},
	{"CB-052", `" G04oui+hEdKIPwAW08ykJw=="`, resumeIDUnreadable},
	{"CB-052", `"1b4e28ba2fa111d2883f0016d3cca427"`, "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	{"CB-052", `"{1b4e28ba-2fa1-11d2-883f-0016d3cca427}"`, "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	{"", `"1b4e28ba-2fa1-11d2-883f-0016d3cca42g"`, resumeIDUnreadable},
	{"", `"1b4e28ba-2fa1-11d2-883f-0016d3cca4270"`, resumeIDUnreadable},
	{"", `"1b4e28ba-2fa1-11d2-883f-0016d3cca42"`, resumeIDUnreadable},
	{"", `"1b4e28ba2-fa1-11d2-883f-0016d3cca427"`, resumeIDUnreadable},
	{"CB-052", `"urn:uuid:1b4e28ba-2fa1-11d2-883f-0016d3cca427"`, "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	{"", `"ffffffff-ffff-ffff-ffff-ffffffffffff"`, "ffffffff-ffff-ffff-ffff-ffffffffffff"},
	{"", `"FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"`, "ffffffff-ffff-ffff-ffff-ffffffffffff"},
	{"", `"1b4e28ba_2fa1_11d2_883f_0016d3cca427"`, resumeIDUnreadable},
	{"", `123`, resumeIDUnreadable},
	{"", `true`, resumeIDUnreadable},
	{"", `[]`, resumeIDUnreadable},
	{"", `{}`, resumeIDUnreadable},
	{"", resumeIDAbsent, resumeIDNoCopy},
}

// TestDecodeBody_ResumeID は、経歴書の作成の resumeId の書き方ごとに、decodeBody が読んだ写す元の ID が表と同じになることと、
// Java 版と答えが違う書き方が、画面が送る書き方でないことを確かめる。
func TestDecodeBody_ResumeID(t *testing.T) {
	for _, tt := range resumeIDTests {
		body := `{"resumeName":"写し"}`
		if tt.input != resumeIDAbsent {
			body = `{"resumeName":"写し","resumeId":` + tt.input + `}`
		}
		got := ""
		req, err := decodeBody[createResumeRequest]([]byte(body))
		switch {
		case err != nil:
			if !errors.Is(err, errUnreadableBody) {
				t.Fatalf("書き方 %s: decodeBody の誤り %v が errUnreadableBody を包んでいない", tt.input, err)
			}
			got = resumeIDUnreadable
		case !req.ResumeID.Present:
			got = resumeIDNoCopy
		default:
			got = req.ResumeID.Value.String()
		}
		if got != tt.want {
			t.Errorf("書き方 %s: 答え %s, want %s", tt.input, got, tt.want)
		}
		// 画面は、resumeId に、答えに返った小文字の形の ID か、空の文字列か null を入れるか、鍵を入れない
		screen := tt.input == resumeIDAbsent ||
			screenValue(reflect.TypeFor[jsonResumeID](), json.RawMessage(tt.input))
		if tt.cb != "" && screen {
			t.Errorf("書き方 %s は画面が送る書き方なのに、%s がある", tt.input, tt.cb)
		}
	}
}

// TestDecodeBody_DiffTableInChangedBehaviors は、本文の読み手のテストの中の表の番号が、変えた動きの一覧にあることを確かめる。
func TestDecodeBody_DiffTableInChangedBehaviors(t *testing.T) {
	t.Run("型の違う値を入れた本文", func(t *testing.T) {
		table := map[string]string{}
		for _, tt := range bodyTests {
			if tt.cb != "" {
				table[tt.name] = tt.cb
			}
		}
		checkDiffTableInChangedBehaviors(t, table)
	})
	t.Run("経歴書の作成の resumeId", func(t *testing.T) {
		table := map[string]string{}
		for _, tt := range resumeIDTests {
			if tt.cb != "" {
				table[tt.input] = tt.cb
			}
		}
		checkDiffTableInChangedBehaviors(t, table)
	})
	t.Run("UTF-8 として誤ったバイト", func(t *testing.T) {
		table := map[string]string{}
		for _, tt := range utf8Tests {
			if tt.cb != "" {
				table[tt.name] = tt.cb
			}
		}
		checkDiffTableInChangedBehaviors(t, table)
	})
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
