//go:build compat

package harness

import (
	"bytes"
	"errors"
	"fmt"
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
	}
	return errors.Join(errs...)
}
