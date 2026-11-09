//go:build compat

package harness

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// realOperations は、backend/api/openapi.yaml の操作を読む。
func realOperations(t *testing.T) Operations {
	t.Helper()
	ops, err := LoadOperations(OpenAPIFile())
	if err != nil {
		t.Fatalf("LoadOperations: %v", err)
	}
	return ops
}

// scenarioOf は、まとまり group の筋書きで、ops の操作を1段ずつ呼ぶ。パスは仕様書の形のまま送る。
func scenarioOf(name string, group int, ops ...Operation) Scenario {
	s := Scenario{Name: name, Group: group, Modes: []string{ModeCompare}}
	for _, op := range ops {
		s.Steps = append(s.Steps, Step{Name: op.ID, Request: Request{Method: op.Method, Path: op.Path}})
	}
	return s
}

func opsOfGroup(ops Operations, group int) Operations {
	var out Operations
	for _, op := range ops {
		if op.Group == group {
			out = append(out, op)
		}
	}
	return out
}

func ids(ops Operations) []string {
	var out []string
	for _, op := range ops {
		out = append(out, op.ID)
	}
	return out
}

// progressWith は、まとまりの表で、states のまとまりをその状態にし、ほかを未着手にした progress.md の本文である。
func progressWith(states map[string]string) string {
	var b strings.Builder
	b.WriteString("# 進み具合\n\n## まとまりの表\n\n状態は次のどれかである。\n\n| まとまり | 子の Issue | spec | 状態 |\n|---|---|---|---|\n")
	for _, name := range []string{"認証", "利用者", "マスタと経歴書", "出力", "バックアップ"} {
		state := states[name]
		if state == "" {
			state = "未着手"
		}
		b.WriteString("| " + name + " | #1 | 未定 | " + state + " |\n")
	}
	b.WriteString("\n- spec の列には、名前を書く\n\n## 次の節\n\n| 認証 | 表ではない | x | y |\n")
	return b.String()
}

// 要件9の受入基準1の土台: 完了と記したまとまりの操作だけを、そのまとまりの筋書きに求める。
func TestCoverageJudge_CompletedOnly(t *testing.T) {
	ops := realOperations(t)
	completed, err := parseCompletedGroups(progressWith(map[string]string{"認証": "作り終えた"}))
	if err != nil || !slices.Equal(completed, []int{GroupAuth}) {
		t.Fatalf("parseCompletedGroups = %v, %v, want [1]", completed, err)
	}
	auth := opsOfGroup(ops, GroupAuth)
	resumes := opsOfGroup(ops, GroupResumes)

	// 認証の13のうち1つが認証の筋書きに無い。経歴書の操作は、まとまりが未着手なので求めない
	partial := []Scenario{scenarioOf("auth", GroupAuth, auth[1:]...), scenarioOf("resumes", GroupResumes, resumes[0])}
	if got := ids(MissingOperations(ops, partial, completed, false)); !slices.Equal(got, []string{auth[0].ID}) {
		t.Errorf("足りない操作 = %v, want [%s]", got, auth[0].ID)
	}
	// ほかのまとまりの筋書きに出てきても、そのまとまりの筋書きに出てきたことにしない
	elsewhere := append(partial, scenarioOf("users", GroupUsers, auth[0]))
	if got := ids(MissingOperations(ops, elsewhere, completed, false)); !slices.Equal(got, []string{auth[0].ID}) {
		t.Errorf("ほかのまとまりの筋書きのとき、足りない操作 = %v, want [%s]", got, auth[0].ID)
	}
	full := []Scenario{scenarioOf("auth-a", GroupAuth, auth[:5]...), scenarioOf("auth-b", GroupAuth, auth[5:]...)}
	if got := MissingOperations(ops, full, completed, false); len(got) != 0 {
		t.Errorf("認証の13がそろっているのに、足りない操作 = %v", ids(got))
	}
	// 完了と記したまとまりが無ければ、何も求めない
	if got := MissingOperations(ops, nil, nil, false); len(got) != 0 {
		t.Errorf("完了したまとまりが無いのに、足りない操作 = %v", ids(got))
	}
	// 完了と記す3つの状態は、どれも完了として読む
	for _, state := range []string{"作り終えた", "比べる検査に通った", "本番で動いている"} {
		got, err := parseCompletedGroups(progressWith(map[string]string{"出力": state, "利用者": "spec の作成中"}))
		if err != nil || !slices.Equal(got, []int{GroupExport}) {
			t.Errorf("状態 %s: parseCompletedGroups = %v, %v, want [4]", state, got, err)
		}
	}
}

// 要件9の受入基準1の土台: 段階4の切り替えの準備では、仕様書の50の操作のすべてを筋書きに求める。
func TestCoverageJudge_All50(t *testing.T) {
	ops := realOperations(t)
	if len(ops) != 50 {
		t.Fatalf("仕様書の操作 = %d, want 50", len(ops))
	}
	for group, want := range map[int]int{GroupAuth: 13, GroupUsers: 7, GroupResumes: 26, GroupExport: 2, GroupBackup: 2} {
		if got := len(opsOfGroup(ops, group)); got != want {
			t.Errorf("まとまり %d の操作 = %d, want %d", group, got, want)
		}
	}
	var scenarios []Scenario
	for group := GroupAuth; group <= GroupBackup; group++ {
		scenarios = append(scenarios, scenarioOf("g", group, opsOfGroup(ops, group)...))
	}
	if got := MissingOperations(ops, scenarios, nil, true); len(got) != 0 {
		t.Errorf("50がそろっているのに、足りない操作 = %v", ids(got))
	}
	// 1つ抜くと、完了と記したまとまりが無くても、その操作を足りないとする
	last := scenarios[len(scenarios)-1]
	dropped := last.Steps[0].Name
	scenarios[len(scenarios)-1].Steps = last.Steps[1:]
	if got := ids(MissingOperations(ops, scenarios, nil, true)); !slices.Equal(got, []string{dropped}) {
		t.Errorf("足りない操作 = %v, want [%s]", got, dropped)
	}
	// すべてを求めないときは、完了と記したまとまりが無いので、何も求めない
	if got := MissingOperations(ops, scenarios, nil, false); len(got) != 0 {
		t.Errorf("すべてを求めないのに、足りない操作 = %v", ids(got))
	}
}

func TestParseCompletedGroups_Errors(t *testing.T) {
	for name, tc := range map[string]struct {
		text, want string
	}{
		"知らない状態":    {progressWith(map[string]string{"認証": "終わった"}), "終わった"},
		"知らないまとまり":  {strings.Replace(progressWith(nil), "| 出力 |", "| 印刷 |", 1), "印刷"},
		"まとまりが足りない": {strings.Replace(progressWith(nil), "| バックアップ | #1 | 未定 | 未着手 |\n", "", 1), "バックアップ"},
		"表が無い":      {"# 進み具合\n", "まとまりの表"},
		"列が足りない":    {strings.Replace(progressWith(nil), "| 出力 | #1 | 未定 | 未着手 |", "| 出力 | 未着手 |", 1), "出力"},
		"同じまとまりが2行": {strings.Replace(progressWith(nil), "| 出力 | #1 | 未定 | 未着手 |", "| 出力 | #1 | 未定 | 未着手 |\n| 出力 | #1 | 未定 | 未着手 |", 1), "出力"},
	} {
		if _, err := parseCompletedGroups(tc.text); err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%s: 誤り = %v, want %q を含む誤り", name, err, tc.want)
		}
	}
	if _, err := LoadCompletedGroups(filepath.Join(t.TempDir(), "none.md")); err == nil {
		t.Error("無いファイルで誤りを返しませんでした")
	}
}

func TestOperations_Lookup(t *testing.T) {
	ops := realOperations(t)
	for _, tc := range []struct{ method, path, want string }{
		{"POST", "/api/auth/login", "login"},
		{"POST", "/api/resumes/restore", "restoreResume"},
		{"GET", "/api/resumes/{resume}", "getResume"},
		{"GET", "/api/resumes/00000000-0000-4000-8000-000000000201", "getResume"},
		{"PUT", "/api/resumes/{resume}/careers/{career}", "updateCareer"},
		{"POST", "/api/resumes/{resume}/export?format=pdf", "exportResumeWithSettings"},
		{"delete", "/api/users/me/auth-provider/google", "removeAuthProvider"},
		// 筋書きの {名前} は、仕様書の決まった文字の部分には当たらない
		{"POST", "/api/resumes/{resume}", ""},
		{"GET", "/healthz", ""},
		{"GET", "/api/resumes/{resume}/basic", ""},
		{"GET", "/api/resumes/x/y/z/w", ""},
	} {
		if got := ops.Lookup(tc.method, tc.path); got != tc.want {
			t.Errorf("Lookup(%s %s) = %q, want %q", tc.method, tc.path, got, tc.want)
		}
	}
}

func TestLoadOperations_Errors(t *testing.T) {
	write := func(content string) string {
		file := filepath.Join(t.TempDir(), "openapi.yaml")
		if err := os.WriteFile(file, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		return file
	}
	ops, err := LoadOperations(write("paths:\n  /a/{id}:\n    parameters: [{name: id, in: path}]\n    get: {operationId: getA}\n    summary: x\n"))
	if err != nil || len(ops) != 1 || ops[0] != (Operation{ID: "getA", Method: "GET", Path: "/a/{id}", Group: GroupResumes}) {
		t.Errorf("LoadOperations = %+v, %v", ops, err)
	}
	for name, tc := range map[string]struct{ content, want string }{
		"operationId が無い": {"paths:\n  /a:\n    get: {summary: x}\n", "/a"},
		"同じ operationId":  {"paths:\n  /a:\n    get: {operationId: x}\n  /b:\n    get: {operationId: x}\n", "x"},
		"paths が無い":       {"openapi: 3.1.0\n", "paths"},
		"YAML として読めない":    {"paths: [\n", "openapi.yaml"},
		"操作の形が誤っている":      {"paths:\n  /a:\n    get: [1]\n", "/a"},
	} {
		if _, err := LoadOperations(write(tc.content)); err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%s: 誤り = %v, want %q を含む誤り", name, err, tc.want)
		}
	}
	if _, err := LoadOperations(filepath.Join(t.TempDir(), "none.yaml")); err == nil {
		t.Error("無いファイルで誤りを返しませんでした")
	}
}

func TestComparer_DropRepeated(t *testing.T) {
	c := NewComparer("s")
	seen := map[string]bool{}
	step1 := StepRef{Index: 1, Name: "create", Operation: "createResume"}
	step2 := StepRef{Index: 2, Name: "read", Operation: "getResume"}
	from := len(c.diffs)
	c.add(step1, TargetDB, "resumes", "a", "b")
	c.dropRepeated(from, seen)
	// 応答の違いは、状態の違いを比べる前に足すので、状態の違いと同じ中身でも消さない
	c.add(step2, TargetBody, "$.name", "x", "y")
	from = len(c.diffs)
	// 1段目と同じ状態の違いは、2段目の操作の違いとして重ねて報告しない
	c.add(step2, TargetDB, "resumes", "a", "b")
	c.add(step2, TargetDB, "users", "c", "d")
	c.dropRepeated(from, seen)
	got := c.Diffs()
	if len(got) != 3 || got[0].Step.Index != 1 || got[1].Target != TargetBody || got[2].Path != "users" {
		t.Errorf("違い = %+v, want 1段目の resumes、2段目の本文と users", got)
	}
}
