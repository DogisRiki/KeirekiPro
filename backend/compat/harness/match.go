//go:build compat

package harness

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"go.yaml.in/yaml/v3"
)

// ChangedBehavior は、変えた動きの一覧(changed-behaviors.yaml)の1つの項目である。
// Matches が空の項目は、比べる検査の違いを許さない、記録だけの項目である。
type ChangedBehavior struct {
	ID       string  `yaml:"id"`
	Group    int     `yaml:"group"`
	Behavior string  `yaml:"変えた動き"`
	Java     string  `yaml:"java"`
	Go       string  `yaml:"go"`
	Reason   string  `yaml:"画面に影響が無い理由"`
	Matches  Matches `yaml:"match"`
}

// Match は、比べる検査が違いを許す範囲である。
type Match struct {
	// Operation は、仕様書の操作の名前(operationId)である。"*" はすべての操作に当たる。
	Operation string `yaml:"operation"`
	// Target は、比べるもの(TargetBody など)である。
	Target string `yaml:"target"`
	// Path は、比べるものの中の場所である。本文なら JSON の場所で、[*] はどの位置の要素にも当たる。
	// 本文の項目は、その場所と、その下の場所の違いに当たる。ヘッダの項目では、ヘッダの名前である。空ならどの場所にも当たる。
	Path string `yaml:"path"`
	// OrderOnly が true の項目は、Path の並びの、要素の順だけの違いを許す。Path は [*] で終わる本文の場所である。
	// Target が redis のときは、Path はキーの形(path.Match の形)で、Field の名前のハッシュの項目の、
	// カンマで区切った要素の順だけの違いを許す。
	OrderOnly bool `yaml:"order_only"`
	// Field は、Target が redis の OrderOnly の項目の、ハッシュの項目の名前である。ほかの項目には書かない。
	Field string `yaml:"field"`
	// Status を書いた項目は、Java 版と Go 版の応答のステータスがどちらもその値のときだけ当たる。0 は書いていないことを表す。
	Status int `yaml:"status"`
}

// Matches は、1つの項目の match である。YAML では、1つの形と並びの形の両方で書ける。
type Matches []Match

// UnmarshalYAML は、match を、1つの形と並びの形の両方から読む。
func (m *Matches) UnmarshalYAML(node *yaml.Node) error {
	if node.Kind == yaml.SequenceNode {
		var list []Match
		if err := node.Decode(&list); err != nil {
			return err
		}
		if len(list) == 0 {
			return errors.New("match の並びが空です。match の無い項目は、match を書かずに記録だけの項目にします")
		}
		*m = list
		return nil
	}
	var one Match
	if err := node.Decode(&one); err != nil {
		return err
	}
	*m = Matches{one}
	return nil
}

var (
	behaviorID = regexp.MustCompile(`^CB-\d{3}$`)
	// jsonPathSegment は、JSON の場所の1つの区切りである。diffJSON が書く場所の形と同じにする。
	jsonPathSegment = regexp.MustCompile(`^(?:\.[A-Za-z_][A-Za-z0-9_]*|\[\*\]|\[\d+\]|\["(?:[^"\\]|\\.)*"\])`)
	knownTargets    = []string{TargetStatus, TargetHeader, TargetBody, TargetDB, TargetRedis, TargetS3, TargetMail, TargetPDF}
)

// LoadChangedBehaviors は、変えた動きの一覧を読み、欄がそろっているかを確かめる。
func LoadChangedBehaviors(file string) ([]ChangedBehavior, error) {
	data, err := os.ReadFile(filepath.Clean(file))
	if err != nil {
		return nil, fmt.Errorf("harness: 変えた動きの一覧 %s を読めません: %w", file, err)
	}
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	var list []ChangedBehavior
	if err := dec.Decode(&list); err != nil {
		return nil, fmt.Errorf("harness: 変えた動きの一覧 %s の形が誤っています: %w", file, err)
	}
	var errs []error
	seen := map[string]bool{}
	for i, b := range list {
		errs = append(errs, b.validate(i+1, seen)...)
	}
	if err := errors.Join(errs...); err != nil {
		return nil, fmt.Errorf("harness: 変えた動きの一覧 %s: %w", file, err)
	}
	return list, nil
}

func (b ChangedBehavior) validate(index int, seen map[string]bool) []error {
	var errs []error
	where := fmt.Sprintf("%d 番目の項目(%s)", index, b.ID)
	switch {
	case !behaviorID.MatchString(b.ID):
		errs = append(errs, fmt.Errorf("%s: id は CB- と3桁の数の形で書きます", where))
	case seen[b.ID]:
		errs = append(errs, fmt.Errorf("%s: id が重なっています", where))
	}
	seen[b.ID] = true
	if b.Group <= 0 {
		errs = append(errs, fmt.Errorf("%s: group がありません", where))
	}
	for name, v := range map[string]string{"変えた動き": b.Behavior, "java": b.Java, "go": b.Go, "画面に影響が無い理由": b.Reason} {
		if strings.TrimSpace(v) == "" {
			errs = append(errs, fmt.Errorf("%s: %s がありません", where, name))
		}
	}
	for j, m := range b.Matches {
		if err := m.validate(); err != nil {
			errs = append(errs, fmt.Errorf("%s の %d 番目の match: %w", where, j+1, err))
		}
	}
	return errs
}

func (m Match) validate() error {
	switch {
	case m.Operation == "":
		return errors.New("operation がありません")
	case !slices.Contains(knownTargets, m.Target):
		return fmt.Errorf("target %q は比べるものの名前ではありません(%s)", m.Target, strings.Join(knownTargets, " / "))
	case m.Target == TargetHeader && m.Path == "":
		return errors.New("target が header の match には、path にヘッダの名前を書きます")
	case m.Status != 0 && (m.Status < 100 || m.Status > 599):
		return fmt.Errorf("status %d は HTTP のステータスではありません", m.Status)
	}
	if m.Target == TargetBody && m.Path != "" {
		segments, err := splitJSONPath(m.Path)
		if err != nil {
			return err
		}
		if m.OrderOnly && (len(segments) == 0 || segments[len(segments)-1] != "[*]") {
			return fmt.Errorf("order_only の match の path %q は、[*] で終わる並びの場所にします", m.Path)
		}
	}
	switch {
	case m.OrderOnly && m.Target == TargetRedis:
		if m.Path == "" || m.Field == "" {
			return errors.New("target が redis の order_only の match には、path にキーの形を、field にハッシュの項目の名前を書きます")
		}
		if _, err := path.Match(m.Path, ""); err != nil {
			return fmt.Errorf("path %q はキーの形として読めません: %w", m.Path, err)
		}
	case m.Field != "":
		return errors.New("field は、target が redis の order_only の match にだけ書きます")
	case m.OrderOnly && (m.Target != TargetBody || m.Path == ""):
		return errors.New("order_only の match は、target を body か redis にし、path に並びの場所を書きます")
	}
	return nil
}

// sortRedisOrderOnly は、Redis の順だけの違いを許す項目に当たるハッシュの項目の値を、カンマで区切った要素の順に
// 並べ替えた写しを返す。両方の版で同じ規則で並べ替えるので、要素が同じなら、並べ替えたあとの値も同じになる。
func sortRedisOrderOnly(behaviors []ChangedBehavior, step StepRef, entries []RedisEntry) []RedisEntry {
	out := slices.Clone(entries)
	for _, b := range behaviors {
		for _, m := range b.Matches {
			if !m.OrderOnly || m.Target != TargetRedis || !m.applies(step) {
				continue
			}
			for i, e := range out {
				if ok, err := path.Match(m.Path, e.Key); ok && err == nil && e.Type == "hash" {
					out[i].Value = sortHashField(e.Value, m.Field)
				}
			}
		}
	}
	return out
}

// sortHashField は、DumpRedis の形のハッシュの値 value の、項目 field の値の要素を並べ替える。
// 値が " で囲まれていれば(Java 版と Go 版が書く JSON の文字の形)、囲みの中を並べ替える。項目が無ければ元のまま返す。
func sortHashField(value, field string) string {
	var fields map[string]string
	if json.Unmarshal([]byte(value), &fields) != nil {
		return value
	}
	v, ok := fields[field]
	if !ok {
		return value
	}
	inner, quoted := v, false
	if len(v) >= 2 && strings.HasPrefix(v, `"`) && strings.HasSuffix(v, `"`) {
		inner, quoted = v[1:len(v)-1], true
	}
	items := strings.Split(inner, ",")
	slices.Sort(items)
	inner = strings.Join(items, ",")
	if quoted {
		inner = `"` + inner + `"`
	}
	fields[field] = inner
	return canonicalJSON(fields)
}

// splitJSONPath は、$ で始まる JSON の場所を区切りに分ける。
func splitJSONPath(path string) ([]string, error) {
	rest, ok := strings.CutPrefix(path, "$")
	if !ok {
		return nil, fmt.Errorf("本文の path %q は $ で始めます", path)
	}
	var segments []string
	for rest != "" {
		seg := jsonPathSegment.FindString(rest)
		if seg == "" {
			return nil, fmt.Errorf("本文の path %q の %q を JSON の場所として読めません", path, rest)
		}
		segments = append(segments, seg)
		rest = rest[len(seg):]
	}
	return segments, nil
}

// applies は、項目が段 step に当たるかを、操作の名前とステータスで確かめる。
func (m Match) applies(step StepRef) bool {
	if m.Operation != "*" && m.Operation != step.Operation {
		return false
	}
	return m.Status == 0 || (step.JavaStatus == m.Status && step.GoStatus == m.Status)
}

// allows は、順だけの違いを許すのでない項目が、違い d を許すかを返す。
func (m Match) allows(d Diff) bool {
	if m.OrderOnly || m.Target != d.Target || !m.applies(d.Step) {
		return false
	}
	switch {
	case m.Path == "":
		return true
	case m.Target == TargetHeader:
		return strings.EqualFold(m.Path, d.Path)
	case m.Target == TargetBody:
		return jsonPathPattern(m.Path).MatchString(d.Path)
	default:
		return m.Path == d.Path
	}
}

// jsonPathPattern は、JSON の場所を、その場所とその下の場所に当たる正規表現にする。[*] はどの位置にも当たる。
func jsonPathPattern(path string) *regexp.Regexp {
	quoted := strings.ReplaceAll(regexp.QuoteMeta(path), `\[\*\]`, `\[\d+\]`)
	return regexp.MustCompile(`^` + quoted + `(?:$|[.\[])`)
}

// AllowedDiff は、変えた動きの一覧の項目が許した違いである。報告に残す。
type AllowedDiff struct {
	ID   string
	Diff Diff
}

// allowedBy は、違い d を許す項目の番号を返す。許す項目が無ければ空を返す。
func allowedBy(behaviors []ChangedBehavior, d Diff) string {
	for _, b := range behaviors {
		for _, m := range b.Matches {
			if m.allows(d) {
				return b.ID
			}
		}
	}
	return ""
}

// sortOrderOnly は、順だけの違いを許す項目の並びを、版ごとの Normalizer の仮の記号で正規化した値の順に並べ替える。
// 両方の版で同じ規則で並べ替えるので、中身が同じ要素の並びなら、並べ替えたあとの順も同じになる。
// 並べ替えたあとに UUID の番号を付けるので、番号は、両方の版で同じ中身の要素にそろう。
func sortOrderOnly(behaviors []ChangedBehavior, step StepRef, n *Normalizer, v any) {
	for _, b := range behaviors {
		for _, m := range b.Matches {
			if !m.OrderOnly || m.Target != TargetBody || !m.applies(step) {
				continue
			}
			segments, err := splitJSONPath(m.Path)
			if err != nil || len(segments) == 0 {
				continue
			}
			walkJSONPath(v, segments[:len(segments)-1], func(found any) {
				if arr, ok := found.([]any); ok {
					slices.SortStableFunc(arr, func(a, b any) int {
						return strings.Compare(canonicalJSON(n.value(a, false)), canonicalJSON(n.value(b, false)))
					})
				}
			})
		}
	}
}

// walkJSONPath は、v の中の、区切り segments の場所にあるすべての値に f を呼ぶ。
func walkJSONPath(v any, segments []string, f func(any)) {
	if len(segments) == 0 {
		f(v)
		return
	}
	seg, rest := segments[0], segments[1:]
	switch {
	case seg == "[*]":
		if arr, ok := v.([]any); ok {
			for _, item := range arr {
				walkJSONPath(item, rest, f)
			}
		}
	case strings.HasPrefix(seg, `["`):
		key, err := strconv.Unquote(seg[1 : len(seg)-1])
		if obj, ok := v.(map[string]any); ok && err == nil {
			if child, ok := obj[key]; ok {
				walkJSONPath(child, rest, f)
			}
		}
	case strings.HasPrefix(seg, "["):
		i, err := strconv.Atoi(seg[1 : len(seg)-1])
		if arr, ok := v.([]any); ok && err == nil && i < len(arr) {
			walkJSONPath(arr[i], rest, f)
		}
	default:
		if obj, ok := v.(map[string]any); ok {
			if child, ok := obj[seg[1:]]; ok {
				walkJSONPath(child, rest, f)
			}
		}
	}
}
