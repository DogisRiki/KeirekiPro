package resume

import (
	"os"
	"sort"
	"testing"

	"go.yaml.in/yaml/v3"
)

// changedBehaviorsFile は、変えた動きの一覧である。go test は、パッケージのフォルダを作業の場所にして動く。
const changedBehaviorsFile = "../../compat/changed-behaviors.yaml"

// checkDiffTableInChangedBehaviors は、テストの中の表の番号が、すべて変えた動きの一覧にあることを確かめる。
// 表は、Go 版の部品の答えが Java 版と違う書き方ごとに、その違いを載せた一覧の番号を持つ。
// Claude が違いを一覧に載せ忘れたことを見つけるために使う。
func checkDiffTableInChangedBehaviors(t *testing.T, table map[string]string) {
	t.Helper()
	if len(table) == 0 {
		t.Fatal("表に書き方が無い")
	}
	b, err := os.ReadFile(changedBehaviorsFile)
	if err != nil {
		t.Fatal(err)
	}
	var items []struct {
		ID string `yaml:"id"`
	}
	if err := yaml.Unmarshal(b, &items); err != nil {
		t.Fatal(err)
	}
	known := map[string]bool{}
	for _, it := range items {
		known[it.ID] = true
	}
	inputs := make([]string, 0, len(table))
	for input := range table {
		inputs = append(inputs, input)
	}
	sort.Strings(inputs)
	for _, input := range inputs {
		if id := table[input]; !known[id] {
			t.Errorf("書き方 %s の番号 %q は、%s に無い", input, id, changedBehaviorsFile)
		}
	}
}
