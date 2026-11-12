//go:build compat

package harness

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

// まとまりの表の状態である。
var (
	// completedStates は、まとまりを完了と記す状態である。比べる検査は、このまとまりの操作を筋書きに求める。
	completedStates = []string{"作り終えた", "比べる検査に通った", "本番で動いている"}
	// knownStates は、まとまりの表に書ける状態である。
	knownStates = append([]string{"未着手", "spec の作成中"}, completedStates...)
)

// progressHeading は、progress.md のまとまりの表の見出しである。
const progressHeading = "## まとまりの表"

// ProgressFile は、リポジトリの最上位からの、Go 版への置き換えの進み具合のファイル progress.md のパスを返す。
func ProgressFile() (string, error) {
	root, err := RepoRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(root, ".kiro", "specs", "backend-go-replacement", "progress.md"), nil
}

// LoadCompletedGroups は、progress.md のまとまりの表を読み、完了と記したまとまりの番号を小さい順に返す。
func LoadCompletedGroups(file string) ([]int, error) {
	data, err := os.ReadFile(filepath.Clean(file))
	if err != nil {
		return nil, fmt.Errorf("harness: 進み具合のファイル %s を読めません: %w", file, err)
	}
	groups, err := parseCompletedGroups(string(data))
	if err != nil {
		return nil, fmt.Errorf("harness: 進み具合のファイル %s: %w", file, err)
	}
	return groups, nil
}

// parseCompletedGroups は、まとまりの表の行を読み、完了と記したまとまりの番号を小さい順に返す。
// 表は、見出し「## まとまりの表」から次の見出しまでの、| で始まる行である。1つ目の列をまとまりの名前、4つ目の列を状態として読む。
// 知らないまとまりと知らない状態と、表に無いまとまりがあれば、誤りを返す。書き誤りで確かめる操作が減らないようにするためである。
func parseCompletedGroups(text string) ([]int, error) {
	_, section, ok := strings.Cut(text, progressHeading+"\n")
	if !ok {
		return nil, fmt.Errorf("見出し %q がありません", progressHeading)
	}
	if i := strings.Index(section, "\n## "); i >= 0 {
		section = section[:i]
	}
	var errs []error
	var completed []int
	seen := map[string]bool{}
	header := true
	for line := range strings.Lines(section) {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "|") {
			continue
		}
		if header || strings.HasPrefix(line, "|---") || strings.HasPrefix(line, "| ---") {
			header = false
			continue
		}
		cells := strings.Split(strings.Trim(line, "|"), "|")
		for i := range cells {
			cells[i] = strings.TrimSpace(cells[i])
		}
		name := cells[0]
		group, ok := GroupNames[name]
		switch {
		case !ok:
			errs = append(errs, fmt.Errorf("まとまり %q は知らない名前です", name))
			continue
		case len(cells) != 4:
			errs = append(errs, fmt.Errorf("まとまり %s の行の列が %d 個です。4 個にしてください", name, len(cells)))
			continue
		case seen[name]:
			errs = append(errs, fmt.Errorf("まとまり %s の行が2つ以上あります", name))
			continue
		}
		seen[name] = true
		state := cells[3]
		if !slices.Contains(knownStates, state) {
			errs = append(errs, fmt.Errorf("まとまり %s の状態 %q は %v のどれでもありません", name, state, knownStates))
			continue
		}
		if slices.Contains(completedStates, state) {
			completed = append(completed, group)
		}
	}
	for _, name := range sortedKeys(GroupNames) {
		if !seen[name] {
			errs = append(errs, fmt.Errorf("まとまり %s の行がありません", name))
		}
	}
	if err := errors.Join(errs...); err != nil {
		return nil, err
	}
	slices.Sort(completed)
	return completed, nil
}

// MissingOperations は、筋書きに出てこない操作を、ops の順に返す。
// completed のまとまりの操作は、そのまとまりの筋書き(group がそのまとまりの番号の筋書き)に1回以上出てこなければならない。
// requireAll が true のときは、そのうえで、ops のすべての操作が、どれかの筋書きに1回以上出てこなければならない。
func MissingOperations(ops Operations, scenarios []Scenario, completed []int, requireAll bool) Operations {
	inGroup := map[int]map[string]bool{}
	anywhere := map[string]bool{}
	for _, s := range scenarios {
		for _, step := range s.Steps {
			// 版に送る段だけが backend の操作を呼ぶ
			if step.Kind() != StepVersion {
				continue
			}
			id := ops.Lookup(step.Request.Method, step.Request.Path)
			if id == "" {
				continue
			}
			if inGroup[s.Group] == nil {
				inGroup[s.Group] = map[string]bool{}
			}
			inGroup[s.Group][id] = true
			anywhere[id] = true
		}
	}
	var missing Operations
	for _, op := range ops {
		if (requireAll && !anywhere[op.ID]) || (slices.Contains(completed, op.Group) && !inGroup[op.Group][op.ID]) {
			missing = append(missing, op)
		}
	}
	return missing
}
