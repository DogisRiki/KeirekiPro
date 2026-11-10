//go:build compat

package harness

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestLoadScenario_ReadsExpectFields(t *testing.T) {
	file := writeScenario(t, strings.Replace(designScenario, "    capture: {}\n    expect: {status: 200}",
		"    capture: {token: $.token}\n    expect: {status: 200, fields: [$.token, $.user.id]}", 1))
	s, err := LoadScenario(file)
	if err != nil {
		t.Fatalf("LoadScenario: %v", err)
	}
	if got := s.Steps[0].Expect.Fields; !slices.Equal(got, []string{"$.token", "$.user.id"}) {
		t.Errorf("fields = %v", got)
	}
	if got := s.Steps[0].Capture["token"]; got != "$.token" {
		t.Errorf("capture = %q", got)
	}
}

func TestLoadScenario_RejectsBadPathsAndCrossWithoutStatus(t *testing.T) {
	for name, tc := range map[string]struct {
		from, to string
		want     []string
	}{
		"capture の場所": {"    capture: {}\n", "    capture: {token: token}\n", []string{"capture token", `"token"`}},
		"fields の場所":  {"    expect: {status: 200}\n  - name: save", "    expect: {status: 200, fields: [x]}\n  - name: save", []string{"fields", `"x"`}},
		"status の無い段": {"      json: {name: 新しい名前}\n    expect: {status: 200}\n", "      json: {name: 新しい名前}\n", []string{"save-basic", "status"}},
	} {
		_, err := LoadScenario(writeScenario(t, strings.Replace(designScenario, tc.from, tc.to, 1)))
		if err == nil {
			t.Errorf("%s: 誤った筋書きを受け付けました", name)
			continue
		}
		for _, w := range tc.want {
			if !strings.Contains(err.Error(), w) {
				t.Errorf("%s: 誤り = %v, want %q を含む", name, err, w)
			}
		}
	}

	oneStep := designScenario[:strings.Index(designScenario, "  - name: save-basic")]
	if _, err := LoadScenario(writeScenario(t, oneStep)); err == nil || !strings.Contains(err.Error(), "2つ以上") {
		t.Errorf("1段の cross の筋書きの誤り = %v", err)
	}
	// cross で動かない筋書きは、1段でも status が無くてもよい
	compareOnly := strings.Replace(strings.Replace(oneStep, "modes: [compare, cross]", "modes: [compare]", 1), "    expect: {status: 200}\n", "", 1)
	if _, err := LoadScenario(writeScenario(t, compareOnly)); err != nil {
		t.Errorf("compare だけの筋書き: %v", err)
	}
}

func TestLoadScenarios_WalksFoldersAndFiltersMode(t *testing.T) {
	dir := t.TempDir()
	write := func(rel, content string) {
		t.Helper()
		file := filepath.Join(dir, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(file), 0o750); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(file, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write("2/b.yaml", strings.Replace(designScenario, "name: login-and-save-basic", "name: b", 1))
	write("1/a.yaml", strings.Replace(designScenario, "name: login-and-save-basic", "name: a", 1))
	write("1/c.yaml", strings.Replace(strings.Replace(designScenario, "name: login-and-save-basic", "name: c", 1), "modes: [compare, cross]", "modes: [compare]", 1))
	write("1/notes.md", "筋書きではない")

	got, err := LoadScenarios(dir, ModeCross)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, s := range got {
		names = append(names, s.Name)
	}
	if !slices.Equal(names, []string{"a", "b"}) {
		t.Errorf("cross の筋書き = %v, want [a b]", names)
	}
	if got, err := LoadScenarios(dir, ModeCompare); err != nil || len(got) != 3 {
		t.Errorf("compare の筋書き = %d 件, %v, want 3 件", len(got), err)
	}

	write("3/broken.yaml", "name: x\nunknown: 1\n")
	if _, err := LoadScenarios(dir, ModeCross); err == nil || !strings.Contains(err.Error(), "broken.yaml") {
		t.Errorf("読めない筋書きの誤り = %v", err)
	}
	if got, err := LoadScenarios(filepath.Join(dir, "none"), ModeCross); err != nil || len(got) != 0 {
		t.Errorf("無いフォルダ = %v, %v, want 空", got, err)
	}
	if filepath.Base(ScenariosDir()) != "scenarios" || filepath.Base(filepath.Dir(ScenariosDir())) != "compat" {
		t.Errorf("ScenariosDir = %s", ScenariosDir())
	}
}
