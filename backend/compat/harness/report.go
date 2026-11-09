//go:build compat

package harness

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

// Report は、1つの筋書きの違いの報告である。
// 前の段の違いが後の段の違いを生むことがあるので、違いの見つかった最初の段の違いを先頭に置く。
type Report struct {
	Scenario string
	// Diffs は、段の順に並べた違いである。同じ段の中では、見つけた順のままにする。
	Diffs []Diff
}

// NewReport は、筋書き scenario の違いを、段の順に並べた報告にする。
func NewReport(scenario string, diffs []Diff) Report {
	sorted := slices.Clone(diffs)
	slices.SortStableFunc(sorted, func(a, b Diff) int { return a.Step.Index - b.Step.Index })
	return Report{Scenario: scenario, Diffs: sorted}
}

// Report は、これまでに見つけた違いの報告を返す。
func (c *Comparer) Report() Report {
	return NewReport(c.Scenario, c.diffs)
}

// Failed は、報告に違いがあるかを返す。
func (r Report) Failed() bool {
	return len(r.Diffs) > 0
}

// String は、報告を、人が読む文にする。違いごとに、筋書きの名前、段、比べたもの、Java 版の値、Go 版の値を書く。
func (r Report) String() string {
	var b strings.Builder
	fmt.Fprintf(&b, "筋書き: %s\n", r.Scenario)
	if !r.Failed() {
		b.WriteString("違い: 0 件\n")
		return b.String()
	}
	first := r.Diffs[0].Step
	fmt.Fprintf(&b, "違い: %d 件(最初に違いが見つかった段: %s)\n", len(r.Diffs), describeStep(first))
	for i, d := range r.Diffs {
		fmt.Fprintf(&b, "\n[%d] 筋書き: %s / 段: %s\n", i+1, r.Scenario, describeStep(d.Step))
		fmt.Fprintf(&b, "    比べたもの: %s", d.Target)
		if d.Path != "" {
			fmt.Fprintf(&b, " / 場所: %s", d.Path)
		}
		if d.Step.JavaStatus != 0 || d.Step.GoStatus != 0 {
			fmt.Fprintf(&b, " / ステータス: Java 版 %d、Go 版 %d", d.Step.JavaStatus, d.Step.GoStatus)
		}
		b.WriteString("\n")
		writeValue(&b, "Java 版", d.Java)
		writeValue(&b, "Go 版", d.Go)
	}
	return b.String()
}

func describeStep(s StepRef) string {
	text := fmt.Sprintf("%d「%s」", s.Index, s.Name)
	if s.Operation != "" {
		text += "(操作 " + s.Operation + ")"
	}
	return text
}

// writeValue は、値を書く。複数の行の値は、2行目からも字下げする。
func writeValue(b *strings.Builder, label, value string) {
	fmt.Fprintf(b, "    %s: %s\n", label, strings.ReplaceAll(value, "\n", "\n        "))
}

var unsafeFileChars = regexp.MustCompile(`[^\p{L}\p{N}_.-]+`)

// Write は、報告を dir の <筋書きの名前>.txt に書き、書いたファイルのパスを返す。
// 比べる検査は、dir に ReportDir を渡し、CI はこのフォルダを成果物に残す。
func (r Report) Write(dir string) (string, error) {
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return "", fmt.Errorf("harness: 報告のフォルダ %s を作れません: %w", dir, err)
	}
	name := unsafeFileChars.ReplaceAllString(r.Scenario, "_")
	if name == "" || strings.Trim(name, ".") == "" {
		name = "scenario"
	}
	file := filepath.Join(dir, name+".txt")
	if err := os.WriteFile(file, []byte(r.String()), 0o600); err != nil {
		return "", fmt.Errorf("harness: 報告 %s を書けません: %w", file, err)
	}
	return file, nil
}
