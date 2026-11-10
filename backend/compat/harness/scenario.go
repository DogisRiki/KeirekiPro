//go:build compat

package harness

import (
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"

	"go.yaml.in/yaml/v3"
)

// 筋書きの動かし方である。
const (
	// ModeCompare は、Java 版と Go 版を別々のデータベースと Redis につなぎ、同じ要求を送って比べる動かし方である。
	ModeCompare = "compare"
	// ModeCross は、Java 版と Go 版を同じデータベースと Redis につなぎ、段ごとに送り先を替える動かし方である。
	ModeCross = "cross"
	// ModePerf は、Java 版と Go 版の応答の時間を比べる動かし方である。
	ModePerf = "perf"
)

// 版をまたぐ動かし方での、段の送り先である。
const (
	// ToSame は、前の段と同じ版に送ることを表す。書かないときもこの値とみなす。
	ToSame = "same"
	// ToOther は、前の段と違う版に送ることを表す。
	ToOther = "other"
)

var (
	knownModes = []string{ModeCompare, ModeCross, ModePerf}
	knownTos   = []string{ToSame, ToOther}
)

// Scenario は、design.md の「筋書きのファイルの形」の1つの筋書きである。
type Scenario struct {
	Name     string   `yaml:"name"`
	Group    int      `yaml:"group"`
	Fixtures []string `yaml:"fixtures"`
	Modes    []string `yaml:"modes"`
	Steps    []Step   `yaml:"steps"`
	// MeasureMemory が true のとき、応答の時間の比べ方は、最後の段を同時に PerfConcurrency 件送ったときの、
	// Go 版のコンテナのメモリの最大も測る。PDF の出力の筋書きに書く。
	MeasureMemory bool `yaml:"measure_memory"`
}

// Step は、筋書きの1つの段である。
type Step struct {
	Name    string            `yaml:"name"`
	To      string            `yaml:"to"`
	Request Request           `yaml:"request"`
	Capture map[string]string `yaml:"capture"`
	Expect  Expect            `yaml:"expect"`
}

// Request は、段で送る要求である。
type Request struct {
	Method  string            `yaml:"method"`
	Path    string            `yaml:"path"`
	Headers map[string]string `yaml:"headers"`
	// CSRF が true のとき、検査は Cookie XSRF-TOKEN の値をヘッダ X-XSRF-TOKEN に写して送る。
	CSRF bool `yaml:"csrf"`
	// JSON は、本文に JSON で送る値である。
	JSON any `yaml:"json"`
}

// Expect は、版をまたぐ動かし方で確かめる応答である。
type Expect struct {
	Status int `yaml:"status"`
	// Fields は、応答の本文の JSON に無ければならない項目の場所($ で始める)である。
	Fields []string `yaml:"fields"`
}

// HasMode は、筋書きがその動かし方で動くかを返す。
func (s Scenario) HasMode(mode string) bool {
	return slices.Contains(s.Modes, mode)
}

// LoadScenario は、筋書きのファイルを読み、形を確かめて返す。
// 筋書きに無い欄と、決めていない動かし方と送り先は、書き誤りとして失敗にする。
func LoadScenario(file string) (Scenario, error) {
	data, err := os.ReadFile(filepath.Clean(file))
	if err != nil {
		return Scenario{}, fmt.Errorf("harness: 筋書き %s を読めません: %w", file, err)
	}
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	var s Scenario
	if err := dec.Decode(&s); err != nil {
		return Scenario{}, fmt.Errorf("harness: 筋書き %s の形が誤っています: %w", file, err)
	}
	if err := s.validate(); err != nil {
		return Scenario{}, fmt.Errorf("harness: 筋書き %s: %w", file, err)
	}
	return s, nil
}

// ScenariosDir は、筋書きのファイルのフォルダ backend/compat/scenarios/ を返す。筋書きは、まとまりごとのフォルダに置く。
func ScenariosDir() string {
	return filepath.Join(FixturesDir(), "..", "scenarios")
}

// LoadScenarios は、dir の下のすべての .yaml のファイルを、パスの順に読み、mode で動く筋書きを返す。
// dir が無いときは、筋書きが無いとして空を返す。1つでも読めない筋書きがあれば、誤りを返す。
func LoadScenarios(dir, mode string) ([]Scenario, error) {
	if _, err := os.Stat(dir); errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	var files []string
	err := filepath.WalkDir(dir, func(file string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !d.IsDir() && filepath.Ext(file) == ".yaml" {
			files = append(files, file)
		}
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("harness: 筋書きのフォルダ %s を読めません: %w", dir, err)
	}
	var scenarios []Scenario
	var errs []error
	for _, file := range files {
		s, err := LoadScenario(file)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		if s.HasMode(mode) {
			scenarios = append(scenarios, s)
		}
	}
	return scenarios, errors.Join(errs...)
}

func (s Scenario) validate() error {
	var errs []error
	if s.Name == "" {
		errs = append(errs, errors.New("name がありません"))
	}
	if len(s.Modes) == 0 {
		errs = append(errs, errors.New("modes がありません"))
	}
	for _, mode := range s.Modes {
		if !slices.Contains(knownModes, mode) {
			errs = append(errs, fmt.Errorf("動かし方 %q は %v のどれでもありません", mode, knownModes))
		}
	}
	if len(s.Steps) == 0 {
		errs = append(errs, errors.New("steps がありません"))
	}
	for i, step := range s.Steps {
		if step.Name == "" {
			errs = append(errs, fmt.Errorf("%d 番目の段に name がありません", i+1))
		}
		if step.To != "" && !slices.Contains(knownTos, step.To) {
			errs = append(errs, fmt.Errorf("段 %s の送り先 %q は %v のどれでもありません", step.Name, step.To, knownTos))
		}
		if step.Request.Method == "" || step.Request.Path == "" {
			errs = append(errs, fmt.Errorf("段 %s の request に method と path がありません", step.Name))
		}
		for _, name := range sortedKeys(step.Capture) {
			if _, err := splitJSONPath(step.Capture[name]); err != nil {
				errs = append(errs, fmt.Errorf("段 %s の capture %s: %w", step.Name, name, err))
			}
		}
		for _, path := range step.Expect.Fields {
			if _, err := splitJSONPath(path); err != nil {
				errs = append(errs, fmt.Errorf("段 %s の expect の fields: %w", step.Name, err))
			}
		}
	}
	if s.HasMode(ModeCross) {
		errs = append(errs, s.validateCross()...)
	}
	errs = append(errs, s.validatePerf()...)
	return errors.Join(errs...)
}

// validatePerf は、応答の時間の比べ方の欄を確かめる。
// 測るのは最後の段なので、最後の段が成功したかを確かめるために、最後の段の expect の status を求める。
// 失敗の応答の時間を測っても、操作の時間を比べたことにならないためである。
func (s Scenario) validatePerf() []error {
	if !s.HasMode(ModePerf) {
		if s.MeasureMemory {
			return []error{fmt.Errorf("measure_memory は、動かし方 %s の筋書きにだけ書けます", ModePerf)}
		}
		return nil
	}
	if len(s.Steps) == 0 {
		return nil
	}
	last := s.Steps[len(s.Steps)-1]
	if last.Expect.Status == 0 {
		return []error{fmt.Errorf("動かし方 %s の筋書きの最後の段 %s に expect の status がありません", ModePerf, last.Name)}
	}
	return nil
}

// validateCross は、版をまたぐ動かし方で動く筋書きの形を確かめる。
// 版をまたぐには2つ以上の段が要る。どの段も、ステータスを確かめないと、もう一方の版で失敗した操作を見逃すので、
// expect の status を求める。
func (s Scenario) validateCross() []error {
	var errs []error
	if len(s.Steps) < 2 {
		errs = append(errs, fmt.Errorf("動かし方 %s の筋書きには2つ以上の段が要りますが、%d 段です", ModeCross, len(s.Steps)))
	}
	for _, step := range s.Steps {
		if step.Expect.Status == 0 {
			errs = append(errs, fmt.Errorf("動かし方 %s の筋書きの段 %s に expect の status がありません", ModeCross, step.Name))
		}
	}
	return errs
}
