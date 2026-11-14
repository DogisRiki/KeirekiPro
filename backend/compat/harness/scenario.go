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
	// Multipart は、版に送る段で、本文に multipart で送る部分の並びである。JSON と一緒には書けない。
	Multipart []MultipartPart `yaml:"multipart"`
	// BodyFile は、絶対の URL の段で、本文にそのまま入れて送る、fixtures/images の下のファイルの名前である。
	// Headers の Content-Type と一緒に使う。JSON と一緒には書けない。
	BodyFile string `yaml:"body_file"`
}

// MultipartPart は、multipart で送る本文の1つの部分である。Value と File のどちらか1つを書く。
type MultipartPart struct {
	// Name は、部分の名前である。
	Name string `yaml:"name"`
	// Value は、文字の値の部分で送る値である。空の文字列を送れるように、書かないときと区別する。
	Value *string `yaml:"value"`
	// File は、ファイルの部分で送る、fixtures/images の下のファイルの名前である。
	File string `yaml:"file"`
	// Filename は、ファイルの部分で送るファイルの名前である。File の部分にだけ書ける。
	Filename string `yaml:"filename"`
	// ContentType は、ファイルの部分の Content-Type である。File の部分にだけ書ける。
	ContentType string `yaml:"content_type"`
	// PadTo は、ファイルの後ろに 0 のバイトを足して、ファイルをこの大きさ(バイト)にする値である。File の部分にだけ書け、
	// ファイルの大きさより小さくできない。
	PadTo int `yaml:"pad_to"`
}

// Expect は、段の応答で確かめることである。
type Expect struct {
	Status int `yaml:"status"`
	// Fields は、応答の本文の JSON に無ければならない項目の場所($ で始める)である。
	Fields []string `yaml:"fields"`
	// Values は、版に送る段で、応答の本文の JSON の場所($ で始める)と、そこにあるはずの値の組である。値には {名前} を差し込める。
	Values map[string]any `yaml:"values"`
	// BodyFile は、絶対の URL の段で、応答の本文とバイトの単位で同じはずの、fixtures/images の下のファイルの名前である。
	BodyFile string `yaml:"body_file"`
	// ContentType は、絶対の URL の段で、応答の Content-Type にあるはずの値である。
	ContentType string `yaml:"content_type"`
}

// imagesFixtureDir は、筋書きが送る画像と、応答と比べる画像を置くフォルダ fixtures/images/ である。
const imagesFixtureDir = "images"

// imageFixtureSize は、fixtures/images の下のファイル name の大きさ(バイト)を返す。
// fixtures/images の外を指す名前と、フォルダと、無いファイルは誤りにする。
func imageFixtureSize(name string) (int64, error) {
	root, err := os.OpenRoot(filepath.Join(FixturesDir(), imagesFixtureDir))
	if err != nil {
		return 0, fmt.Errorf("画像のフォルダ fixtures/images を開けません: %w", err)
	}
	defer func() { _ = root.Close() }()
	info, err := root.Stat(filepath.FromSlash(name))
	if err != nil {
		return 0, fmt.Errorf("fixtures/images にありません: %w", err)
	}
	if !info.Mode().IsRegular() {
		return 0, errors.New("fixtures/images のファイルではありません")
	}
	return info.Size(), nil
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
		for _, path := range sortedKeys(step.Expect.Values) {
			if _, err := splitJSONPath(path); err != nil {
				errs = append(errs, fmt.Errorf("段 %s の expect の values: %w", step.Name, err))
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
		len(s.Request.Headers) > 0 || s.Request.CSRF || s.Request.JSON != nil ||
		len(s.Request.Multipart) > 0 || s.Request.BodyFile != ""
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
		return s.validateVersionBody()
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

// validateVersionBody は、版に送る段の本文の欄を確かめる。multipart の部分ごとの欄を確かめ、
// 絶対の URL の段にだけ書ける request の body_file と、expect の body_file と content_type が無いかを確かめる。
func (s Step) validateVersionBody() []error {
	var errs []error
	if s.Request.JSON != nil && len(s.Request.Multipart) > 0 {
		errs = append(errs, fmt.Errorf("段 %s の request の json と multipart は一緒に書けません", s.Name))
	}
	for i, part := range s.Request.Multipart {
		errs = append(errs, part.validate(s.Name, i+1)...)
	}
	if s.Request.BodyFile != "" {
		errs = append(errs, fmt.Errorf("段 %s の request の body_file は、絶対の URL の段にだけ書けます", s.Name))
	}
	if s.Expect.BodyFile != "" {
		errs = append(errs, fmt.Errorf("段 %s の expect の body_file は、絶対の URL の段にだけ書けます", s.Name))
	}
	if s.Expect.ContentType != "" {
		errs = append(errs, fmt.Errorf("段 %s の expect の content_type は、絶対の URL の段にだけ書けます", s.Name))
	}
	return errs
}

// validate は、段 step の n 番目の multipart の部分の欄を確かめる。
func (p MultipartPart) validate(step string, n int) []error {
	var errs []error
	if p.Name == "" {
		errs = append(errs, fmt.Errorf("段 %s の multipart の %d 番目の部分に name がありません", step, n))
	}
	if (p.Value != nil) == (p.File != "") {
		errs = append(errs, fmt.Errorf("段 %s の multipart の %d 番目の部分には value と file のどちらか1つを書きます", step, n))
	}
	if p.File == "" {
		if p.Filename != "" || p.ContentType != "" || p.PadTo != 0 {
			errs = append(errs, fmt.Errorf("段 %s の multipart の %d 番目の部分の filename と content_type と pad_to は、file の部分にだけ書けます", step, n))
		}
		return errs
	}
	size, err := imageFixtureSize(p.File)
	if err != nil {
		return append(errs, fmt.Errorf("段 %s の multipart の %d 番目の部分の file %q: %w", step, n, p.File, err))
	}
	if p.PadTo != 0 && int64(p.PadTo) < size {
		errs = append(errs, fmt.Errorf("段 %s の multipart の %d 番目の部分の pad_to %d は、file %q の大きさ %d バイトより小さくできません", step, n, p.PadTo, p.File, size))
	}
	return errs
}

// validateAbsoluteURL は、絶対の URL の段の欄を確かめる。
// この段の応答は偽のログインのサービスか偽の AWS が作るので、版の Cookie の束から作る csrf と、版の応答の項目を確かめる
// fields と values を書けない。本文は、版に送る段の multipart の代わりに、body_file で送る。
func (s Step) validateAbsoluteURL() []error {
	var errs []error
	if s.Request.Method == "" {
		errs = append(errs, fmt.Errorf("段 %s の request に method がありません", s.Name))
	}
	if s.Request.Path != "" {
		errs = append(errs, fmt.Errorf("段 %s の request に path と url の両方があります", s.Name))
	}
	if !absoluteURLTemplate(s.Request.URL) {
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
	if len(s.Expect.Values) > 0 {
		errs = append(errs, fmt.Errorf("段 %s の expect の values は、版に送る段にだけ書けます", s.Name))
	}
	if len(s.Request.Multipart) > 0 {
		errs = append(errs, fmt.Errorf("段 %s の request の multipart は、版に送る段にだけ書けます", s.Name))
	}
	if s.Request.BodyFile != "" {
		if s.Request.JSON != nil {
			errs = append(errs, fmt.Errorf("段 %s の request の json と body_file は一緒に書けません", s.Name))
		}
		if _, err := imageFixtureSize(s.Request.BodyFile); err != nil {
			errs = append(errs, fmt.Errorf("段 %s の request の body_file %q: %w", s.Name, s.Request.BodyFile, err))
		}
	}
	if s.Expect.BodyFile != "" {
		if _, err := imageFixtureSize(s.Expect.BodyFile); err != nil {
			errs = append(errs, fmt.Errorf("段 %s の expect の body_file %q: %w", s.Name, s.Expect.BodyFile, err))
		}
	}
	return errs
}

// absoluteURLTemplate は、絶対の URL の段の url raw が、差し込む前の形として正しいかを返す。
// 差し込む名前 {名前} で始まる url は、前の段で取り出した URL の頭か全体を差し込むので、読み込みのときには確かめず、
// 送るときに SendAbsolute が、差し込んだあとの url を確かめる。それ以外の url は、差し込む名前を仮の文字 x に置き換えて、
// スキームとホストのある絶対の URL かを確かめる。
func absoluteURLTemplate(raw string) bool {
	if loc := pathVariable.FindStringIndex(raw); loc != nil && loc[0] == 0 {
		return true
	}
	u, err := url.Parse(pathVariable.ReplaceAllString(raw, "x"))
	return err == nil && u.IsAbs() && u.Host != ""
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
	if s.Expect.Status != 0 || len(s.Expect.Fields) > 0 || len(s.Expect.Values) > 0 ||
		s.Expect.BodyFile != "" || s.Expect.ContentType != "" {
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
