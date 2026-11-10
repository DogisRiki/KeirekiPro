//go:build compat

package harness

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReport_FirstDiffStepFirst(t *testing.T) {
	login := StepRef{Index: 1, Name: "login", Operation: "login", JavaStatus: 200, GoStatus: 200}
	save := StepRef{Index: 2, Name: "save-basic", Operation: "updateBasic", JavaStatus: 200, GoStatus: 400}
	check := StepRef{Index: 3, Name: "check-db"}

	c := NewComparer("login-and-save-basic")
	// 後の段の違いを先に見つけた場面である。報告では、段の順に並べ直す。
	c.CompareDB(check, DBSnapshot{"resumes": {{"name": "a"}}}, DBSnapshot{"resumes": {{"name": "b"}}})
	c.CompareResponse(save, jsonResponse(200, `{"name":"a"}`), jsonResponse(400, `{"name":"a","x":1}`))
	c.CompareResponse(login, jsonResponse(200, `{"line":"一\n二"}`), jsonResponse(200, `{"line":"一\n三"}`))

	report := c.Report()
	if !report.Failed() || len(report.Diffs) != 4 {
		t.Fatalf("報告の違い = %+v", report.Diffs)
	}
	wantSteps := []int{1, 2, 2, 3}
	wantTargets := []string{TargetBody, TargetStatus, TargetBody, TargetDB}
	for i, d := range report.Diffs {
		if d.Step.Index != wantSteps[i] || d.Target != wantTargets[i] {
			t.Errorf("違い[%d] = 段 %d %s, want 段 %d %s", i, d.Step.Index, d.Target, wantSteps[i], wantTargets[i])
		}
	}
	// 段の違う違いを含めても、元の違いの並びは変えない。
	if c.Diffs()[0].Target != TargetDB {
		t.Errorf("比べた順の違い = %+v", c.Diffs())
	}

	text := report.String()
	wantHeader := "筋書き: login-and-save-basic\n違い: 4 件(最初に違いが見つかった段: 1「login」(操作 login))\n"
	if !strings.HasPrefix(text, wantHeader) {
		t.Fatalf("報告の始め = %q, want %q", text, wantHeader)
	}
	wantFirst := "\n[1] 筋書き: login-and-save-basic / 段: 1「login」(操作 login)\n" +
		"    比べたもの: body / 場所: $.line / ステータス: Java 版 200、Go 版 200\n" +
		"    Java 版: \"一\\n二\"\n" +
		"    Go 版: \"一\\n三\"\n"
	if !strings.Contains(text, wantFirst) {
		t.Errorf("最初の違いの文がありません:\n%s", text)
	}
	if !strings.Contains(text, "[2] 筋書き: login-and-save-basic / 段: 2「save-basic」(操作 updateBasic)\n    比べたもの: status / ステータス: Java 版 200、Go 版 400\n") {
		t.Errorf("ステータスの違いの文がありません:\n%s", text)
	}
	if !strings.Contains(text, "[4] 筋書き: login-and-save-basic / 段: 3「check-db」\n    比べたもの: db / 場所: resumes\n") {
		t.Errorf("操作の無い段の違いの文がありません:\n%s", text)
	}
	if strings.Index(text, "段: 1「login」") > strings.Index(text, "段: 3「check-db」") {
		t.Errorf("最初の段の違いが先頭にありません:\n%s", text)
	}

	t.Run("複数の行の値は2行目からも字下げする", func(t *testing.T) {
		r := NewReport("s", []Diff{{Scenario: "s", Step: check, Target: TargetDB, Path: "users", Java: "行1\n行2", Go: absent}})
		if !strings.Contains(r.String(), "    Java 版: 行1\n        行2\n    Go 版: (無し)\n") {
			t.Errorf("報告 = %q", r.String())
		}
	})
	t.Run("違いが無い報告", func(t *testing.T) {
		r := NewComparer("s").Report()
		if r.Failed() || r.String() != "筋書き: s\n違い: 0 件\n" {
			t.Errorf("報告 = %v %q", r.Failed(), r.String())
		}
	})
	t.Run("報告をファイルに書く", func(t *testing.T) {
		dir := filepath.Join(t.TempDir(), "reports")
		file, err := report.Write(dir)
		if err != nil {
			t.Fatalf("Write: %v", err)
		}
		if file != filepath.Join(dir, "login-and-save-basic.txt") {
			t.Errorf("書いたファイル = %s", file)
		}
		got, err := os.ReadFile(filepath.Clean(file))
		if err != nil || string(got) != text {
			t.Errorf("書いた中身 = %q, %v", got, err)
		}
		for scenario, want := range map[string]string{"../経歴 書/x": ".._経歴_書_x.txt", "..": "scenario.txt", "": "scenario.txt"} {
			file, err := NewReport(scenario, nil).Write(dir)
			if err != nil || filepath.Base(file) != want || filepath.Dir(file) != dir {
				t.Errorf("筋書き %q の報告のファイル = %s, %v, want %s", scenario, file, err, want)
			}
		}
		blocker := filepath.Join(t.TempDir(), "file")
		if err := os.WriteFile(blocker, nil, 0o600); err != nil {
			t.Fatal(err)
		}
		if _, err := report.Write(filepath.Join(blocker, "sub")); err == nil {
			t.Error("フォルダを作れないのに誤りになりません")
		}
	})
}
