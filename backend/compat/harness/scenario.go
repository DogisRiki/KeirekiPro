//go:build compat

package harness

import (
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"net/url"
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
	// PrepareEach が true のとき、応答の時間の比べ方は、慣らしの回と測る回のそれぞれの前に、最後の段より前の段を送り直す。
	// 2段階認証の確認のコードのように、1回使うと消える値を最後の段で使う筋書きに書く。
	PrepareEach bool `yaml:"prepare_each"`
	// OIDCUsers は、筋書きの始めに偽のログインのサービスに登録する、Google と GitHub でログインする利用者である。
	OIDCUsers *OIDCUsers `yaml:"oidc_users"`
}

// OIDCUsers は、筋書きの始めに偽のログインのサービスに登録する利用者である。書かない提供元には登録しない。
type OIDCUsers struct {
	Google *OIDCGoogleUser `yaml:"google"`
	GitHub *OIDCGitHubUser `yaml:"github"`
}

// OIDCGoogleUser は、Google の userinfo が返す利用者の値である。
// harness は、偽のログインのサービスの /_compat/users/google の口へ、この値を JSON にして送る。
type OIDCGoogleUser struct {
	Sub           string `yaml:"sub" json:"sub"`
	Name          string `yaml:"name" json:"name"`
	Email         string `yaml:"email" json:"email"`
	EmailVerified bool   `yaml:"email_verified" json:"email_verified"`
}

// OIDCGitHubUser は、GitHub の /user と /user/emails が返す利用者の値である。
// harness は、偽のログインのサービスの /_compat/users/github の口へ、この値を JSON にして送る。
type OIDCGitHubUser struct {
	ID     int64             `yaml:"id" json:"id"`
	Login  string            `yaml:"login" json:"login"`
	Emails []OIDCGitHubEmail `yaml:"emails" json:"emails"`
}

// OIDCGitHubEmail は、GitHub の /user/emails が返すメールアドレスの1件である。
type OIDCGitHubEmail struct {
	Email    string `yaml:"email" json:"email"`
	Primary  bool   `yaml:"primary" json:"primary"`
	Verified bool   `yaml:"verified" json:"verified"`
}

// StepKind は、段の種類である。1つの段は、どれか1つの種類だけを持つ。
type StepKind int

// 段の種類である。
const (
	// StepVersion は、request の method と path を持ち、版に送る段である。
	StepVersion StepKind = iota + 1
	// StepAbsoluteURL は、request の method と url を持ち、偽のログインのサービスの絶対の URL へ送る段である。
	StepAbsoluteURL
	// StepRedis は、redis を持ち、要求を送らずに版の Redis を書き換える段である。
	StepRedis
	// StepExpire は、expire を持ち、要求を送らずに筋書きの中の JWT の値を期限の過ぎた値に書き換える段である。
	StepExpire
)

// Step は、筋書きの1つの段である。
type Step struct {
	Name    string            `yaml:"name"`
	To      string            `yaml:"to"`
	Request Request           `yaml:"request"`
	Redis   *RedisStep        `yaml:"redis"`
	Expire  *ExpireStep       `yaml:"expire"`
	Capture map[string]string `yaml:"capture"`
	Expect  Expect            `yaml:"expect"`
}

// Kind は、段の種類を返す。筋書きを読むときに、段が1つの種類の欄だけを持つことを確かめてある。
func (s Step) Kind() StepKind {
	switch {
	case s.Redis != nil:
		return StepRedis
	case s.Expire != nil:
		return StepExpire
	case s.Request.URL != "":
		return StepAbsoluteURL
	default:
		return StepVersion
	}
}

// RedisStep は、Redis を書き換える段で、版の Redis に行う書き換えである。キーと値には {名前} を差し込める。
type RedisStep struct {
	// Del は、消すキーの並びである。
	Del []string `yaml:"del"`
	// Set は、置くキーと値の並びである。
	Set []RedisSet `yaml:"set"`
}

// RedisSet は、Redis を書き換える段で置く1つのキーと値である。
type RedisSet struct {
	Key string `yaml:"key"`
	// Value は、置く JSON の値の文字列である。
	Value string `yaml:"value"`
	// TTLSeconds は、置く値の有効な時間の秒である。
	TTLSeconds int `yaml:"ttl_seconds"`
}

// ExpireStep は、値を期限切れにする段で、書き換える JWT の値である。Cookie と Var のどちらか1つを書く。
type ExpireStep struct {
	// Cookie は、Cookie の束のうち、書き換える Cookie の名前である。
	Cookie string `yaml:"cookie"`
	// Var は、書き換える取り出した値の名前である。
	Var string `yaml:"var"`
}

// Request は、段で送る要求である。
type Request struct {
	Method string `yaml:"method"`
	// Path は、版に送る段で、版の基底の URL のあとに付ける経路である。
	Path string `yaml:"path"`
	// URL は、絶対の URL の段で送る先の絶対の URL である。Path と一緒には書けない。
	URL     string            `yaml:"url"`
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
		errs = append(errs, step.validateKind()...)
		for _, name := range sortedKeys(step.Capture) {
			if _, err := parseCaptureSource(step.Capture[name]); err != nil {
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

// validateKind は、段が1つの種類の欄だけを持ち、その種類に要る欄があり、ほかの種類の欄が無いかを確かめる。
func (s Step) validateKind() []error {
	hasRequest := s.Request.Method != "" || s.Request.Path != "" || s.Request.URL != "" ||
		len(s.Request.Headers) > 0 || s.Request.CSRF || s.Request.JSON != nil
	kinds := 0
	for _, has := range []bool{hasRequest, s.Redis != nil, s.Expire != nil} {
		if has {
			kinds++
		}
	}
	// どの種類の欄も無い段は、版に送る段として、method と path が無いことで断る
	if kinds > 1 {
		return []error{fmt.Errorf("段 %s は request と redis と expire のうち1つだけを持てます", s.Name)}
	}
	switch s.Kind() {
	case StepVersion:
		if s.Request.Method == "" || s.Request.Path == "" {
			return []error{fmt.Errorf("段 %s の request に method と path がありません", s.Name)}
		}
		return nil
	case StepAbsoluteURL:
		return s.validateAbsoluteURL()
	case StepRedis:
		return append(s.validateRedis(), s.notRequestFields()...)
	default:
		var errs []error
		if (s.Expire.Cookie == "") == (s.Expire.Var == "") {
			errs = append(errs, fmt.Errorf("段 %s の expire には cookie と var のどちらか1つを書きます", s.Name))
		}
		return append(errs, s.notRequestFields()...)
	}
}

// validateAbsoluteURL は、絶対の URL の段の欄を確かめる。
// この段の応答は偽のログインのサービスが作るので、版の Cookie の束から作る csrf と、版の応答の項目を確かめる fields を書けない。
func (s Step) validateAbsoluteURL() []error {
	var errs []error
	if s.Request.Method == "" {
		errs = append(errs, fmt.Errorf("段 %s の request に method がありません", s.Name))
	}
	if s.Request.Path != "" {
		errs = append(errs, fmt.Errorf("段 %s の request に path と url の両方があります", s.Name))
	}
	if u, err := url.Parse(s.Request.URL); err != nil || !u.IsAbs() || u.Host == "" {
		errs = append(errs, fmt.Errorf("段 %s の request の url %q は絶対の URL ではありません", s.Name, s.Request.URL))
	}
	if s.Request.CSRF {
		errs = append(errs, fmt.Errorf("段 %s の request の csrf は、版に送る段にだけ書けます", s.Name))
	}
	if s.To != "" {
		errs = append(errs, fmt.Errorf("段 %s の to は、版に送る段にだけ書けます", s.Name))
	}
	if len(s.Expect.Fields) > 0 {
		errs = append(errs, fmt.Errorf("段 %s の expect の fields は、版に送る段にだけ書けます", s.Name))
	}
	return errs
}

// validateRedis は、Redis を書き換える段の欄を確かめる。
// 置く値には有効な時間を求める。有効な時間の無い値は、筋書きのあとも版の Redis に残り続けるためである。
func (s Step) validateRedis() []error {
	var errs []error
	if len(s.Redis.Del) == 0 && len(s.Redis.Set) == 0 {
		errs = append(errs, fmt.Errorf("段 %s の redis に del と set のどちらもありません", s.Name))
	}
	if slices.Contains(s.Redis.Del, "") {
		errs = append(errs, fmt.Errorf("段 %s の redis の del に空のキーがあります", s.Name))
	}
	for i, set := range s.Redis.Set {
		if set.Key == "" || set.Value == "" || set.TTLSeconds <= 0 {
			errs = append(errs, fmt.Errorf("段 %s の redis の set の %d 番目には key と value と1以上の ttl_seconds が要ります", s.Name, i+1))
		}
	}
	return errs
}

// notRequestFields は、要求を送らない段に、要求の段の欄 to と capture と expect が無いかを確かめる。
func (s Step) notRequestFields() []error {
	var errs []error
	if s.To != "" {
		errs = append(errs, fmt.Errorf("段 %s の to は、版に送る段にだけ書けます", s.Name))
	}
	if len(s.Capture) > 0 {
		errs = append(errs, fmt.Errorf("段 %s は要求を送らないので、capture を書けません", s.Name))
	}
	if s.Expect.Status != 0 || len(s.Expect.Fields) > 0 {
		errs = append(errs, fmt.Errorf("段 %s は要求を送らないので、expect を書けません", s.Name))
	}
	return errs
}

// validatePerf は、応答の時間の比べ方の欄を確かめる。
// 測るのは最後の段なので、最後の段に、版に送る段であることと、成功したかを確かめるための expect の status を求める。
// 失敗の応答の時間を測っても、操作の時間を比べたことにならないためである。
func (s Scenario) validatePerf() []error {
	if !s.HasMode(ModePerf) {
		var errs []error
		if s.MeasureMemory {
			errs = append(errs, fmt.Errorf("measure_memory は、動かし方 %s の筋書きにだけ書けます", ModePerf))
		}
		if s.PrepareEach {
			errs = append(errs, fmt.Errorf("prepare_each は、動かし方 %s の筋書きにだけ書けます", ModePerf))
		}
		return errs
	}
	var errs []error
	// 同時に送る要求が、1回使うと消える1つの値を取り合うためである
	if s.PrepareEach && s.MeasureMemory {
		errs = append(errs, errors.New("prepare_each が真の筋書きには measure_memory を書けません"))
	}
	if len(s.Steps) == 0 {
		return errs
	}
	last := s.Steps[len(s.Steps)-1]
	switch {
	case last.Kind() != StepVersion:
		errs = append(errs, fmt.Errorf("動かし方 %s の筋書きの最後の段 %s は、版に送る段でなければなりません", ModePerf, last.Name))
	case last.Expect.Status == 0:
		errs = append(errs, fmt.Errorf("動かし方 %s の筋書きの最後の段 %s に expect の status がありません", ModePerf, last.Name))
	}
	return errs
}

// validateCross は、版をまたぐ動かし方で動く筋書きの形を確かめる。
// 版を割り当てるのは版に送る段だけなので、版をまたぐには版に送る段が2つ以上要る。版に送る段は、ステータスを確かめないと、
// もう一方の版で失敗した操作を見逃すので、expect の status を求める。最後の段は、版に送る段でなければならない。
func (s Scenario) validateCross() []error {
	var errs []error
	versionSteps := 0
	for _, step := range s.Steps {
		if step.Kind() != StepVersion {
			continue
		}
		versionSteps++
		if step.Expect.Status == 0 {
			errs = append(errs, fmt.Errorf("動かし方 %s の筋書きの段 %s に expect の status がありません", ModeCross, step.Name))
		}
	}
	if versionSteps < 2 {
		errs = append(errs, fmt.Errorf("動かし方 %s の筋書きには版に送る段が2つ以上要りますが、%d 段です", ModeCross, versionSteps))
	}
	if len(s.Steps) > 0 {
		if last := s.Steps[len(s.Steps)-1]; last.Kind() != StepVersion {
			errs = append(errs, fmt.Errorf("動かし方 %s の筋書きの最後の段 %s は、版に送る段でなければなりません", ModeCross, last.Name))
		}
	}
	return errs
}
