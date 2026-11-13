//go:build compat

package harness

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// cb は、テストで使う変えた動きの一覧の項目を作る。
func cb(id string, matches ...Match) ChangedBehavior {
	return ChangedBehavior{ID: id, Group: 1, Behavior: "動き", Java: "Java 版", Go: "Go 版", Reason: "理由", Matches: matches}
}

const (
	portfoliosAB = `{"portfolios":[{"id":"11111111-1111-1111-1111-111111111111","name":"あ"},{"id":"22222222-2222-2222-2222-222222222222","name":"い"}]}`
	portfoliosBA = `{"portfolios":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"い"},{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","name":"あ"}]}`
)

func TestMatch_OrderOnlyAllowsReorder(t *testing.T) {
	orderOnly := cb("CB-001", Match{Operation: "getResume", Target: TargetBody, Path: "$.portfolios[*]", OrderOnly: true})
	step := StepRef{Index: 1, Name: "段1", Operation: "getResume"}

	t.Run("順だけが違うときは止めない", func(t *testing.T) {
		// どちらの版の並びも並べ替えることを確かめるため、Java 版と Go 版の並びを入れ替えても確かめる。
		for _, pair := range [][2]string{{portfoliosAB, portfoliosBA}, {portfoliosBA, portfoliosAB}} {
			c := NewComparer("筋書き")
			c.Behaviors = []ChangedBehavior{orderOnly}
			c.CompareResponse(step, jsonResponse(200, pair[0]), jsonResponse(200, pair[1]))
			if r := c.Report(); r.Failed() {
				t.Fatalf("違いが無いはずですが、%d 件ありました: %+v", len(r.Diffs), r.Diffs)
			}
		}
	})

	t.Run("並べ替えたあとの UUID の番号は、両方の版で同じ中身の要素にそろう", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.Behaviors = []ChangedBehavior{orderOnly}
		c.CompareResponse(step, jsonResponse(200, portfoliosAB), jsonResponse(200, portfoliosBA))
		// 「あ」の UUID は、どちらの版でも <uuid:1> になる。後の段で同じ UUID を使うと、違いが出ない。
		next := StepRef{Index: 2, Name: "段2", Operation: "getPortfolio"}
		c.CompareResponse(next,
			jsonResponse(200, `{"id":"11111111-1111-1111-1111-111111111111"}`),
			jsonResponse(200, `{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}`))
		if r := c.Report(); r.Failed() {
			t.Fatalf("違いが無いはずですが、%d 件ありました: %+v", len(r.Diffs), r.Diffs)
		}
	})

	t.Run("順のほかの違いは止める", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.Behaviors = []ChangedBehavior{orderOnly}
		goBody := strings.Replace(portfoliosBA, `"name":"い"`, `"name":"う"`, 1)
		c.CompareResponse(step, jsonResponse(200, portfoliosAB), jsonResponse(200, goBody))
		r := c.Report()
		if len(r.Diffs) != 1 || r.Diffs[0].Path != "$.portfolios[1].name" {
			t.Fatalf("名前の違いが1件のはずですが、違い = %+v", r.Diffs)
		}
	})

	t.Run("要素の数の違いは止める", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.Behaviors = []ChangedBehavior{orderOnly}
		c.CompareResponse(step, jsonResponse(200, portfoliosAB), jsonResponse(200, `{"portfolios":[]}`))
		if r := c.Report(); len(r.Diffs) != 1 || r.Diffs[0].Path != "$.portfolios" {
			t.Fatalf("並びの違いが1件のはずですが、違い = %+v", r.Diffs)
		}
	})

	t.Run("一覧に無い場所の順の違いは止める", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.Behaviors = []ChangedBehavior{orderOnly}
		j := strings.ReplaceAll(portfoliosAB, "portfolios", "careers")
		g := strings.ReplaceAll(portfoliosBA, "portfolios", "careers")
		c.CompareResponse(step, jsonResponse(200, j), jsonResponse(200, g))
		if r := c.Report(); !r.Failed() {
			t.Fatal("careers の順の違いを見つけるはずですが、違いがありませんでした")
		}
	})

	t.Run("入れ子の場所の並びも並べ替える", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.Behaviors = []ChangedBehavior{cb("CB-001", Match{Operation: "backupResume", Target: TargetBody, Path: "$.resume.portfolios[*]", OrderOnly: true})}
		c.CompareResponse(StepRef{Index: 1, Operation: "backupResume"},
			jsonResponse(200, `{"resume":`+portfoliosAB+`}`), jsonResponse(200, `{"resume":`+portfoliosBA+`}`))
		if r := c.Report(); r.Failed() {
			t.Fatalf("違いが無いはずですが、%d 件ありました: %+v", len(r.Diffs), r.Diffs)
		}
	})
}

func TestMatch_OtherOperationNotAllowed(t *testing.T) {
	behaviors := []ChangedBehavior{
		cb("CB-001", Match{Operation: "getResume", Target: TargetBody, Path: "$.portfolios[*]", OrderOnly: true}),
		cb("CB-100", Match{Operation: "getResume", Target: TargetBody, Path: "$.name"}),
	}

	t.Run("順だけの違いを、ほかの操作では許さない", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.Behaviors = behaviors
		c.CompareResponse(StepRef{Index: 1, Operation: "listResumes"}, jsonResponse(200, portfoliosAB), jsonResponse(200, portfoliosBA))
		if r := c.Report(); !r.Failed() {
			t.Fatal("listResumes の順の違いを見つけるはずですが、違いがありませんでした")
		}
	})

	t.Run("値の違いを、ほかの操作では許さない", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.Behaviors = behaviors
		c.CompareResponse(StepRef{Index: 1, Operation: "listResumes"}, jsonResponse(200, `{"name":"a"}`), jsonResponse(200, `{"name":"b"}`))
		if r := c.Report(); len(r.Diffs) != 1 {
			t.Fatalf("違いが1件のはずですが、違い = %+v", r.Diffs)
		}
	})

	t.Run("同じ操作の、一覧の場所とその下の違いは許し、許した違いとして報告に残す", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.Behaviors = behaviors
		c.CompareResponse(StepRef{Index: 1, Operation: "getResume"},
			jsonResponse(200, `{"name":{"first":"a"},"names":"x"}`), jsonResponse(200, `{"name":{"first":"b"},"names":"y"}`))
		r := c.Report()
		if len(r.Diffs) != 1 || r.Diffs[0].Path != "$.names" {
			t.Fatalf("$.names の違いだけが残るはずですが、違い = %+v", r.Diffs)
		}
		if len(r.Allowed) != 1 || r.Allowed[0].ID != "CB-100" || r.Allowed[0].Diff.Path != "$.name.first" {
			t.Fatalf("許した違いは CB-100 の $.name.first の1件のはずですが、%+v", r.Allowed)
		}
		if !strings.Contains(r.String(), "CB-100") {
			t.Fatalf("報告に、許した違いの項目の番号がありません:\n%s", r.String())
		}
	})
}

func TestMatch_AnyOperation(t *testing.T) {
	behaviors := []ChangedBehavior{cb("CB-001", Match{Operation: "*", Target: TargetBody, Path: "$.portfolios[*]", OrderOnly: true})}
	for _, op := range []string{"getResume", "createPortfolio", "updateResumeBasic"} {
		c := NewComparer("筋書き")
		c.Behaviors = behaviors
		c.CompareResponse(StepRef{Index: 1, Operation: op}, jsonResponse(200, portfoliosAB), jsonResponse(200, portfoliosBA))
		if r := c.Report(); r.Failed() {
			t.Errorf("%s: 違いが無いはずですが、%+v", op, r.Diffs)
		}
	}
	c := NewComparer("筋書き")
	c.Behaviors = behaviors
	c.CompareResponse(StepRef{Index: 1, Operation: "getResume"}, jsonResponse(200, `{"portfolios":[],"x":1}`), jsonResponse(200, `{"portfolios":[],"x":2}`))
	if r := c.Report(); len(r.Diffs) != 1 {
		t.Fatalf("\"*\" の項目でも、ほかの場所の違いは止めるはずですが、違い = %+v", r.Diffs)
	}
}

func TestMatch_StatusLimitsScope(t *testing.T) {
	behaviors := []ChangedBehavior{cb("CB-006", Match{Operation: "*", Target: TargetHeader, Path: "Set-Cookie", Status: 403})}
	resp := func(status int, cookie string) Response {
		h := http.Header{}
		if cookie != "" {
			h.Set("Set-Cookie", cookie)
		}
		return Response{Status: status, Header: h}
	}
	cases := []struct {
		name         string
		java, goResp Response
		cookieStops  bool
	}{
		{"両方の版が 403 なら許す", resp(403, ""), resp(403, "XSRF-TOKEN=v; Path=/"), false},
		{"両方の版が 200 なら許さない", resp(200, ""), resp(200, "XSRF-TOKEN=v; Path=/"), true},
		{"Java 版だけが 403 なら許さない", resp(403, ""), resp(200, "XSRF-TOKEN=v; Path=/"), true},
		{"Go 版だけが 403 なら許さない", resp(200, ""), resp(403, "XSRF-TOKEN=v; Path=/"), true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c := NewComparer("筋書き")
			c.Behaviors = behaviors
			c.CompareResponse(StepRef{Index: 1, Operation: "logout"}, tc.java, tc.goResp)
			got := slices.ContainsFunc(c.Report().Diffs, func(d Diff) bool { return d.Path == "Set-Cookie" })
			if got != tc.cookieStops {
				t.Fatalf("Set-Cookie の違いで止めるか = %v、期待 = %v(違い = %+v)", got, tc.cookieStops, c.Report().Diffs)
			}
		})
	}
	t.Run("403 でも、ほかのものの違いは許さない", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.Behaviors = behaviors
		c.CompareResponse(StepRef{Index: 1, Operation: "logout"}, jsonResponse(403, `{"a":1}`), jsonResponse(403, `{"a":2}`))
		if r := c.Report(); len(r.Diffs) != 1 || r.Diffs[0].Target != TargetBody {
			t.Fatalf("本文の違いが1件のはずですが、違い = %+v", r.Diffs)
		}
	})
}

func TestMatch_HeaderPath(t *testing.T) {
	java := Response{Status: 200, Header: http.Header{"Cache-Control": {"no-cache"}, "Set-Cookie": {"A=1; Path=/"}}}
	goResp := Response{Status: 200, Header: http.Header{"Cache-Control": {"no-store"}, "Set-Cookie": {"A=1; Path=/x"}}}

	t.Run("ヘッダの名前が同じなら、大文字と小文字によらず許す", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.Behaviors = []ChangedBehavior{cb("CB-100", Match{Operation: "*", Target: TargetHeader, Path: "cache-control"})}
		c.CompareResponse(StepRef{Index: 1, Operation: "getResume"}, java, goResp)
		r := c.Report()
		if len(r.Diffs) != 1 || r.Diffs[0].Path != "Set-Cookie" {
			t.Fatalf("Set-Cookie の違いだけが残るはずですが、違い = %+v", r.Diffs)
		}
	})

	t.Run("ヘッダの名前を、名前の頭として読まない", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.Behaviors = []ChangedBehavior{cb("CB-100", Match{Operation: "*", Target: TargetHeader, Path: "Cache"})}
		c.CompareResponse(StepRef{Index: 1, Operation: "getResume"}, java, goResp)
		if r := c.Report(); len(r.Diffs) != 2 {
			t.Fatalf("2件の違いが残るはずですが、違い = %+v", r.Diffs)
		}
	})

	t.Run("本文の場所の項目は、同じ名前のヘッダに当たらない", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.Behaviors = []ChangedBehavior{cb("CB-100", Match{Operation: "*", Target: TargetBody, Path: "Cache-Control"})}
		c.CompareResponse(StepRef{Index: 1, Operation: "getResume"}, java, goResp)
		if r := c.Report(); len(r.Diffs) != 2 {
			t.Fatalf("2件の違いが残るはずですが、違い = %+v", r.Diffs)
		}
	})
}

func writeBehaviors(t *testing.T, body string) string {
	t.Helper()
	file := filepath.Join(t.TempDir(), "changed-behaviors.yaml")
	if err := os.WriteFile(file, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return file
}

const validItem = `- id: CB-001
  group: 3
  変えた動き: 日本語の名前の並び順
  java: Java の規則
  go: Go の規則
  画面に影響が無い理由: 所有者が受け入れた
`

func TestLoadChangedBehaviors_RequiredFields(t *testing.T) {
	t.Run("欄がそろっていれば読める。match は1つの形と並びの形の両方を読める", func(t *testing.T) {
		file := writeBehaviors(t, validItem+`  match:
    operation: getResume
    target: body
    path: $.portfolios[*]
    order_only: true
`+strings.Replace(validItem, "CB-001", "CB-002", 1)+`  match:
    - operation: "*"
      target: header
      path: Set-Cookie
      status: 403
    - operation: backupResume
      target: body
      path: $.resume["sns platforms"][*]
      order_only: true
`)
		got, err := LoadChangedBehaviors(file)
		if err != nil {
			t.Fatal(err)
		}
		if len(got) != 2 || got[0].Behavior != "日本語の名前の並び順" || got[0].Reason != "所有者が受け入れた" {
			t.Fatalf("読んだ項目 = %+v", got)
		}
		if len(got[0].Matches) != 1 || !got[0].Matches[0].OrderOnly || got[0].Matches[0].Path != "$.portfolios[*]" {
			t.Fatalf("CB-001 の match = %+v", got[0].Matches)
		}
		if len(got[1].Matches) != 2 || got[1].Matches[0].Status != 403 || got[1].Matches[1].Operation != "backupResume" {
			t.Fatalf("CB-002 の match = %+v", got[1].Matches)
		}
	})

	broken := map[string]string{
		"id が無い":            strings.Replace(validItem, "- id: CB-001\n  group", "- group", 1),
		"id の形が誤っている":       strings.Replace(validItem, "CB-001", "CB-1", 1),
		"id が重なっている":        validItem + validItem,
		"group が無い":         strings.Replace(validItem, "  group: 3\n", "", 1),
		"変えた動きが無い":          strings.Replace(validItem, "  変えた動き: 日本語の名前の並び順\n", "", 1),
		"java が空":           strings.Replace(validItem, "java: Java の規則", `java: ""`, 1),
		"go が無い":            strings.Replace(validItem, "  go: Go の規則\n", "", 1),
		"画面に影響が無い理由が無い":     strings.Replace(validItem, "  画面に影響が無い理由: 所有者が受け入れた\n", "", 1),
		"知らない欄がある":          validItem + "  memo: x\n",
		"match に操作が無い":      validItem + "  match:\n    target: body\n    path: $.a\n",
		"match の比べるものが誤り":   validItem + "  match:\n    operation: getResume\n    target: bodies\n    path: $.a\n",
		"ヘッダの match に名前が無い": validItem + "  match:\n    operation: getResume\n    target: header\n",
		"順だけの match が本文でない": validItem + "  match:\n    operation: getResume\n    target: db\n    path: resumes\n    order_only: true\n",
		"順だけの match が並びでない": validItem + "  match:\n    operation: getResume\n    target: body\n    path: $.portfolios\n    order_only: true\n",
		"本文の場所の形が誤り":        validItem + "  match:\n    operation: getResume\n    target: body\n    path: portfolios[*]\n",
		"ステータスが誤り":          validItem + "  match:\n    operation: getResume\n    target: status\n    status: 99\n",
		"match が空の並び":       validItem + "  match: []\n",
	}
	for name, body := range broken {
		t.Run(name, func(t *testing.T) {
			if _, err := LoadChangedBehaviors(writeBehaviors(t, body)); err == nil {
				t.Fatal("誤りを返すはずですが、読めました")
			}
		})
	}

	t.Run("ファイルが無ければ誤りを返す", func(t *testing.T) {
		if _, err := LoadChangedBehaviors(filepath.Join(t.TempDir(), "none.yaml")); err == nil {
			t.Fatal("誤りを返すはずですが、読めました")
		}
	})
}

func TestLoadChangedBehaviors_CB005HasNoMatch(t *testing.T) {
	got, err := LoadChangedBehaviors(filepath.Join("..", "changed-behaviors.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	byID := map[string]ChangedBehavior{}
	for _, b := range got {
		byID[b.ID] = b
	}
	for i := 1; i <= 27; i++ {
		if id := fmt.Sprintf("CB-%03d", i); byID[id].ID != id {
			t.Errorf("%s が一覧にありません", id)
		}
	}
	if len(got) != 29 {
		t.Errorf("一覧の項目は29のはずですが、%d です", len(got))
	}
	for _, id := range []string{
		"CB-005", "CB-007", "CB-008", "CB-009", "CB-010",
		"CB-013", "CB-014", "CB-015", "CB-016", "CB-017", "CB-018", "CB-019", "CB-020", "CB-021", "CB-022", "CB-023", "CB-025", "CB-026",
		"CB-027",
	} {
		if m := byID[id].Matches; len(m) != 0 {
			t.Errorf("%s は記録だけの項目のはずですが、match があります: %+v", id, m)
		}
	}
	for _, m := range byID["CB-001"].Matches {
		if !m.OrderOnly || m.Target != TargetBody {
			t.Errorf("CB-001 の match は本文の順だけを許すはずですが、%+v", m)
		}
	}
	if m := byID["CB-006"].Matches; len(m) != 1 || m[0] != (Match{Operation: "*", Target: TargetHeader, Path: "Set-Cookie", Status: 403}) {
		t.Errorf("CB-006 の match = %+v", m)
	}
	// 入力の誤りの文言の並びは、2つ以上の文言を持ちうる操作と項目の、順だけの違いを許す
	wantOrder := []string{
		"registerUser $.errors.email[*]", "registerUser $.errors.username[*]", "registerUser $.errors.password[*]",
		"registerUser $.errors.confirmPassword[*]", "resetPassword $.errors.password[*]",
		"resetPassword $.errors.confirmPassword[*]", "requestPasswordReset $.errors.email[*]",
		"verifyEmail $.errors.token[*]", "resendEmailVerification $.errors.token[*]",
	}
	var gotOrder []string
	for _, m := range byID["CB-011"].Matches {
		if !m.OrderOnly || m.Target != TargetBody || m.Status != 0 {
			t.Errorf("CB-011 の match は本文の順だけを許すはずですが、%+v", m)
		}
		gotOrder = append(gotOrder, m.Operation+" "+m.Path)
	}
	if !slices.Equal(gotOrder, wantOrder) {
		t.Errorf("CB-011 の match の操作と場所 = %v, want %v", gotOrder, wantOrder)
	}
	wantCB012 := Matches{
		{Operation: "startOidcAuthorization", Target: TargetStatus},
		{Operation: "startOidcAuthorization", Target: TargetBody, Path: "$.message"},
	}
	if m := byID["CB-012"].Matches; !slices.Equal(m, wantCB012) {
		t.Errorf("CB-012 の match = %+v, want %+v", m, wantCB012)
	}
	wantCB024 := Matches{
		{Operation: "*", Target: TargetBody, Path: "$.components", Status: 200},
		{Operation: "*", Target: TargetBody, Path: "$.groups", Status: 200},
	}
	if m := byID["CB-024"].Matches; !slices.Equal(m, wantCB024) {
		t.Errorf("CB-024 の match = %+v, want %+v", m, wantCB024)
	}
}

// TestChangedBehaviors_UserItems は、利用者の操作の項目が、並びの順だけの違いを許すことを確かめる。
func TestChangedBehaviors_UserItems(t *testing.T) {
	got, err := LoadChangedBehaviors(filepath.Join("..", "changed-behaviors.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	byID := map[string]ChangedBehavior{}
	for _, b := range got {
		byID[b.ID] = b
	}
	orderOnly := func(operation, path string) Match {
		return Match{Operation: operation, Target: TargetBody, Path: path, OrderOnly: true}
	}
	tests := map[string]Matches{
		// 利用者の情報の役割と連携の並びは、Java 版で決まった順を持たない
		"CB-028": {
			orderOnly("getUserInfo", "$.roles[*]"),
			orderOnly("getUserInfo", "$.authProviders[*]"),
			orderOnly("updateUserInfo", "$.roles[*]"),
			orderOnly("updateUserInfo", "$.authProviders[*]"),
			orderOnly("setEmailAndPassword", "$.roles[*]"),
			orderOnly("setEmailAndPassword", "$.authProviders[*]"),
		},
		// 入力の誤りの文言の並びは、2つ以上の文言を持ちうる操作と項目だけを許す
		"CB-029": {
			orderOnly("changePassword", "$.errors.newPassword[*]"),
			orderOnly("setEmailAndPassword", "$.errors.email[*]"),
			orderOnly("setEmailAndPassword", "$.errors.password[*]"),
		},
	}
	for id, want := range tests {
		t.Run(id, func(t *testing.T) {
			b, ok := byID[id]
			if !ok {
				t.Fatalf("%s が一覧にありません", id)
			}
			if b.Group != 2 {
				t.Errorf("%s の group = %d, want 2", id, b.Group)
			}
			if !slices.Equal(b.Matches, want) {
				t.Errorf("%s の match = %+v, want %+v", id, b.Matches, want)
			}
		})
	}
}
