//go:build compat

package harness

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
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

// Redis のキーの残りの有効な時間は段が進むたびに減るので、値が同じままの違いは、時間が減っても重ねて報告しない。
func TestComparer_DropRepeatedRedisIgnoresTTL(t *testing.T) {
	c := NewComparer("s")
	seen := map[string]bool{}
	step1 := StepRef{Index: 1, Name: "login", Operation: "login"}
	step2 := StepRef{Index: 2, Name: "read", Operation: "getResume"}
	step3 := StepRef{Index: 3, Name: "update", Operation: "updateResume"}
	entry := func(value string, ttl time.Duration) []RedisEntry {
		return []RedisEntry{{Key: "k", Type: "string", Value: value, TTL: ttl}}
	}
	for _, s := range []struct {
		step        StepRef
		java, goVer []RedisEntry
	}{
		{step1, entry("a", 900*time.Second), entry("b", 900*time.Second)},
		// 値の違いは1段目と同じで、両方の版の残りの時間だけが減った
		{step2, entry("a", 897*time.Second), entry("b", 897*time.Second)},
		// 値が変わった違いは、新しい違いとして報告する
		{step3, entry("a", 895*time.Second), entry("c", 895*time.Second)},
	} {
		from := len(c.diffs)
		c.CompareRedis(s.step, s.java, s.goVer)
		c.dropRepeated(from, seen)
	}
	got := c.Diffs()
	if len(got) != 2 || got[0].Step.Index != 1 || got[1].Step.Index != 3 {
		t.Errorf("違い = %+v, want 1段目と3段目の2件", got)
	}
}

// useStep は、筋書きの版に送る段である。to が ToOther なら、送り先の組でもう一方の版へ移る。
func useStep(name, method, path, accept, to string) Step {
	s := Step{Name: name, To: to, Request: Request{Method: method, Path: path}}
	if accept != "" {
		s.Request.Headers = map[string]string{"Accept": accept}
	}
	return s
}

// crossScenarios は、design.md の「cross」の10の操作をそろえた、版をまたぐ動かし方の筋書きである。
func crossScenarios() []Scenario {
	cross := func(name string, steps ...Step) Scenario {
		// 最後の段は、送り先の組がその前の版と違う版に送る、保存した内容を読む段である
		steps = append(steps, useStep("read", "GET", "/api/users/me", "", ""))
		return Scenario{Name: name, Group: GroupAuth, Modes: []string{ModeCompare, ModeCross}, Steps: steps}
	}
	return []Scenario{
		cross("save", useStep("login", "POST", "/api/auth/login", "", ""),
			useStep("update-basic", "PUT", "/api/resumes/{resumeID}/basic", "", "")),
		cross("export", useStep("login", "POST", "/api/auth/login", "", ""),
			useStep("pdf", "POST", "/api/resumes/{resumeID}/export", "application/pdf, application/json", "")),
		cross("refresh-logout", useStep("login", "POST", "/api/auth/login", "", ""),
			useStep("refresh", "POST", "/api/auth/token/refresh", "", ""), useStep("logout", "POST", "/api/auth/logout", "", "")),
		cross("two-factor", useStep("login", "POST", "/api/auth/login", "", ""), useStep("verify", "POST", "/api/auth/2fa/verify", "", "")),
		cross("password-reset", useStep("request", "POST", "/api/auth/password/reset/request", "", ""),
			useStep("verify", "POST", "/api/auth/password/reset/verify", "", ""), useStep("reset", "POST", "/api/auth/password/reset", "", "")),
		cross("register", useStep("register", "POST", "/api/auth/register", "", ""),
			useStep("verify", "POST", "/api/auth/email-verification/verify", "", "")),
		cross("google", useStep("start", "GET", "/api/auth/oidc/authorize?provider=google", "", ""),
			useStep("callback", "GET", "/api/auth/oidc/callback?code={code}&state={state}", "", "")),
		cross("github", useStep("start", "GET", "/api/auth/oidc/authorize?provider=github", "", ""),
			useStep("callback", "GET", "/api/auth/oidc/callback?code={code}&state={state}", "", "")),
		cross("backup", useStep("login", "POST", "/api/auth/login", "", ""),
			useStep("backup", "GET", "/api/resumes/{resumeID}/backup", "application/json", ""),
			useStep("delete", "DELETE", "/api/resumes/{resumeID}", "", ""),
			useStep("restore", "POST", "/api/resumes/restore", "", ToOther)),
	}
}

// replaceScenario は、scenarios の写しで、名前が name の筋書きを s に替える。
func replaceScenario(scenarios []Scenario, name string, s Scenario) []Scenario {
	out := slices.Clone(scenarios)
	for i := range out {
		if out[i].Name == name {
			out[i] = s
		}
	}
	return out
}

func useNames(uses []RequiredUse) []string {
	var out []string
	for _, u := range uses {
		out = append(out, u.Name)
	}
	return out
}

// usesHaveRealOperations は、決めた操作の ID が、すべて仕様書にあることを確かめる。書き誤りで確かめる操作が減らないようにするためである。
func usesHaveRealOperations(t *testing.T, ops Operations, uses []RequiredUse) {
	t.Helper()
	known := map[string]bool{}
	for _, op := range ops {
		known[op.ID] = true
	}
	for _, u := range uses {
		if len(u.Sequences) == 0 {
			t.Errorf("%s: 段の並びがありません", u.Name)
		}
		for _, seq := range u.Sequences {
			for _, step := range seq {
				for _, id := range step.Operations {
					if !known[id] {
						t.Errorf("%s: 操作 %s は仕様書にありません", u.Name, id)
					}
				}
			}
		}
	}
}

// 要件13の受入基準6: 版をまたぐ動かし方の筋書きに、design.md の「cross」の10の操作がそろっていなければ、足りない操作を返す。
func TestCoverageJudge_CrossOperationsMissing(t *testing.T) {
	ops := realOperations(t)
	if got := len(CrossUses); got != 10 {
		t.Errorf("版をまたぐ確認に求める操作 = %d, want 10", got)
	}
	usesHaveRealOperations(t, ops, CrossUses)
	all := crossScenarios()
	missing := func(scenarios []Scenario) []string {
		t.Helper()
		got, err := MissingCrossUses(ops, scenarios)
		if err != nil {
			t.Fatalf("MissingCrossUses: %v", err)
		}
		return got
	}
	if got := missing(all); len(got) != 0 {
		t.Fatalf("10がそろっているのに、足りない操作 = %v", got)
	}
	if got := missing(nil); !slices.Equal(got, useNames(CrossUses)) {
		t.Errorf("筋書きが無いとき、足りない操作 = %v, want 10のすべて", got)
	}
	drop := func(name string) []Scenario {
		return slices.DeleteFunc(slices.Clone(all), func(s Scenario) bool { return s.Name == name })
	}
	withSteps := func(name string, steps ...Step) []Scenario {
		for _, s := range all {
			if s.Name == name {
				s.Steps = steps
				return replaceScenario(all, name, s)
			}
		}
		t.Fatalf("筋書き %s がありません", name)
		return nil
	}
	login := useStep("login", "POST", "/api/auth/login", "", "")
	read := useStep("read", "GET", "/api/users/me", "", "")
	for name, tc := range map[string]struct {
		scenarios []Scenario
		want      []string
	}{
		"ログインせずに保存する": {withSteps("save", useStep("update-basic", "PUT", "/api/resumes/{resumeID}/basic", "", ""), read),
			[]string{"ログインしたままの利用者の保存"}},
		"Markdown だけを出力する": {withSteps("export", login,
			useStep("markdown", "GET", "/api/resumes/{resumeID}/export", "text/markdown, application/json", ""), read),
			[]string{"PDF の出力"}},
		"ログアウトとトークンの更新が無い": {drop("refresh-logout"), []string{"ログアウト", "トークンの更新"}},
		"ログインせずに2段階認証のコードを送る": {withSteps("two-factor", useStep("verify", "POST", "/api/auth/2fa/verify", "", ""), read),
			[]string{"2段階認証"}},
		"再設定のトークンを確かめない": {withSteps("password-reset", useStep("request", "POST", "/api/auth/password/reset/request", "", ""),
			useStep("reset", "POST", "/api/auth/password/reset", "", ""), read),
			[]string{"パスワードの再設定"}},
		"確認を登録より前に送る": {withSteps("register", useStep("verify", "POST", "/api/auth/email-verification/verify", "", ""),
			useStep("register", "POST", "/api/auth/register", "", ""), read),
			[]string{"新規の登録のメールアドレスの確認"}},
		"GitHub でのログインが無い": {drop("github"), []string{"Google と GitHub でのログイン"}},
		// to: other が無いと、交互の組だけが版をまたぐ。交互の組は、1つ目の段を Java 版に送るので、2つ目の段の書き出しを Go 版に、
		// 3つ目の段の戻しを Java 版に送る
		"戻す段が交互の組でだけ版をまたぐ": {withSteps("backup", login,
			useStep("backup", "GET", "/api/resumes/{resumeID}/backup", "application/json", ""),
			useStep("restore", "POST", "/api/resumes/restore", "", ""), read),
			[]string{"Java 版で書き出したバックアップを Go 版で戻すこと"}},
		"戻す段が書き出した版と同じ版に届く": {withSteps("backup", login,
			useStep("backup", "GET", "/api/resumes/{resumeID}/backup", "application/json", ""),
			useStep("delete", "DELETE", "/api/resumes/{resumeID}", "", ""),
			useStep("restore", "POST", "/api/resumes/restore", "", ""),
			useStep("read-resume", "GET", "/api/resumes/{resumeID}", "", ToOther)),
			[]string{"Go 版で書き出したバックアップを Java 版で戻すこと", "Java 版で書き出したバックアップを Go 版で戻すこと"}},
	} {
		if got := missing(tc.scenarios); !slices.Equal(got, tc.want) {
			t.Errorf("%s: 足りない操作 = %v, want %v", name, got, tc.want)
		}
	}
	// 比べる動かし方だけの筋書きは、版をまたぐ確認に数えない
	compareOnly := slices.Clone(all)
	for i := range compareOnly {
		compareOnly[i].Modes = []string{ModeCompare}
	}
	if got := missing(compareOnly); !slices.Equal(got, useNames(CrossUses)) {
		t.Errorf("比べる動かし方だけの筋書きのとき、足りない操作 = %v, want 10のすべて", got)
	}
}

// perfScenarios は、design.md の「perf」の11の操作を、それぞれ最後の段で測る筋書きである。
func perfScenarios() []Scenario {
	perf := func(name string, last Step) Scenario {
		return Scenario{Name: name, Group: GroupResumes, Modes: []string{ModePerf},
			Steps: []Step{useStep("login", "POST", "/api/auth/login", "", ""), last}}
	}
	return []Scenario{
		{Name: "login", Group: GroupAuth, Modes: []string{ModePerf}, Steps: []Step{useStep("login", "POST", "/api/auth/login", "", "")}},
		perf("refresh", useStep("refresh", "POST", "/api/auth/token/refresh", "", "")),
		perf("user-info", useStep("me", "GET", "/api/users/me", "", "")),
		perf("list", useStep("list", "GET", "/api/resumes", "", "")),
		perf("get", useStep("get", "GET", "/api/resumes/{resumeID}", "", "")),
		perf("basic", useStep("basic", "PUT", "/api/resumes/{resumeID}/basic", "", "")),
		perf("career", useStep("career", "POST", "/api/resumes/{resumeID}/careers", "", "")),
		perf("pdf", useStep("pdf", "POST", "/api/resumes/{resumeID}/export", "application/pdf, application/json", "")),
		perf("markdown", useStep("markdown", "GET", "/api/resumes/{resumeID}/export", "text/markdown, application/json", "")),
		perf("backup", useStep("backup", "GET", "/api/resumes/{resumeID}/backup", "application/json", "")),
		perf("restore", useStep("restore", "POST", "/api/resumes/restore", "", "")),
	}
}

// 要件9の受入基準7: 応答の時間の比べ方の筋書きが、design.md の「perf」の11の操作を最後の段で測っていなければ、足りない操作を返す。
func TestCoverageJudge_PerfOperationsMissing(t *testing.T) {
	ops := realOperations(t)
	if got := len(PerfUses); got != 11 {
		t.Errorf("応答の時間を比べる操作 = %d, want 11", got)
	}
	usesHaveRealOperations(t, ops, PerfUses)
	all := perfScenarios()
	if got := MissingPerfUses(ops, all); len(got) != 0 {
		t.Fatalf("11がそろっているのに、足りない操作 = %v", got)
	}
	if got := MissingPerfUses(ops, nil); !slices.Equal(got, useNames(PerfUses)) {
		t.Errorf("筋書きが無いとき、足りない操作 = %v, want 11のすべて", got)
	}
	// 職歴の追加の段が、測る最後の段でなく、準備の段にある
	notLast := all[6]
	notLast.Steps = []Step{notLast.Steps[1], notLast.Steps[0]}
	if got := MissingPerfUses(ops, replaceScenario(all, "career", notLast)); !slices.Equal(got, []string{"職歴の追加"}) {
		t.Errorf("職歴の追加を準備の段で送るとき、足りない操作 = %v, want [職歴の追加]", got)
	}
	// 出力の形は、Accept の行で見分ける
	markdownOnly := all[7]
	markdownOnly.Steps = []Step{all[7].Steps[0], useStep("markdown", "POST", "/api/resumes/{resumeID}/export", "text/markdown, application/json", "")}
	if got := MissingPerfUses(ops, replaceScenario(all, "pdf", markdownOnly)); !slices.Equal(got, []string{"PDF の出力"}) {
		t.Errorf("PDF を測る筋書きが Markdown を求めるとき、足りない操作 = %v, want [PDF の出力]", got)
	}
	// 版をまたぐ動かし方の筋書きは、応答の時間の比べ方に数えない
	crossOnly := all[10]
	crossOnly.Modes = []string{ModeCross}
	if got := MissingPerfUses(ops, replaceScenario(all, "restore", crossOnly)); !slices.Equal(got, []string{"バックアップの戻し"}) {
		t.Errorf("戻しが版をまたぐ動かし方の筋書きにだけあるとき、足りない操作 = %v, want [バックアップの戻し]", got)
	}
}
