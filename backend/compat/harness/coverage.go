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

// UseStep は、design.md が筋書きに求める操作の、1つの段の条件である。
type UseStep struct {
	// Operations は、段の操作の ID の候補である。段の操作が、どれか1つに当たればよい。
	Operations []string
	// Query は、空でなければ、段のパスの ? よりあとに含まれなければならない文字である。
	Query string
	// Accept は、空でなければ、段の Accept の行に含まれなければならない文字である。出力の形を見分ける。
	Accept string
	// Version は、空でなければ、送り先の組で、この段を送る版である。版をまたぐ確認にだけ書く。
	Version string
}

// RequiredUse は、design.md が、1つの動かし方の筋書きに求める操作の1つである。
type RequiredUse struct {
	// Name は、design.md の一覧の言葉である。
	Name string
	// Sequences の段の並びは、それぞれ、1つの筋書きの段に、この順で出てこなければならない。間に別の段があってよい。
	Sequences [][]UseStep
}

// saveOperations は、画面が経歴書と利用者の情報を保存する操作である。
var saveOperations = []string{
	"updateUserInfo", "createResume", "updateResumeBasic",
	"createCareer", "updateCareer", "createProject", "updateProject",
	"createCertification", "updateCertification", "createPortfolio", "updatePortfolio",
	"createSnsPlatform", "updateSnsPlatform", "createSelfPromotion", "updateSelfPromotion",
}

// exportOperations は、経歴書を出力する2つの操作である。どちらも、Accept の行で出力の形を選ぶ。
var exportOperations = []string{"exportResume", "exportResumeWithSettings"}

func requiredUse(name string, sequences ...[]UseStep) RequiredUse {
	return RequiredUse{Name: name, Sequences: sequences}
}

func opStep(ids ...string) UseStep { return UseStep{Operations: ids} }

// CrossUses は、design.md の「cross」が、版をまたぐ動かし方の筋書きに求める10の操作である。
var CrossUses = []RequiredUse{
	requiredUse("ログインしたままの利用者の保存", []UseStep{opStep("login"), opStep(saveOperations...)}),
	requiredUse("PDF の出力", []UseStep{{Operations: exportOperations, Accept: "application/pdf"}}),
	requiredUse("ログアウト", []UseStep{opStep("logout")}),
	requiredUse("トークンの更新", []UseStep{opStep("refreshToken")}),
	requiredUse("2段階認証", []UseStep{opStep("login"), opStep("verifyTwoFactorAuth")}),
	requiredUse("パスワードの再設定", []UseStep{opStep("requestPasswordReset"), opStep("verifyPasswordResetToken"), opStep("resetPassword")}),
	requiredUse("新規の登録のメールアドレスの確認", []UseStep{opStep("registerUser"), opStep("verifyEmail")}),
	requiredUse("Google と GitHub でのログイン",
		[]UseStep{{Operations: []string{"startOidcAuthorization"}, Query: "provider=google"}, opStep("handleOidcCallback")},
		[]UseStep{{Operations: []string{"startOidcAuthorization"}, Query: "provider=github"}, opStep("handleOidcCallback")}),
	requiredUse("Go 版で書き出したバックアップを Java 版で戻すこと",
		[]UseStep{{Operations: []string{"backupResume"}, Version: VersionGo}, {Operations: []string{"restoreResume"}, Version: VersionJava}}),
	requiredUse("Java 版で書き出したバックアップを Go 版で戻すこと",
		[]UseStep{{Operations: []string{"backupResume"}, Version: VersionJava}, {Operations: []string{"restoreResume"}, Version: VersionGo}}),
}

// PerfUses は、design.md の「perf」が、応答の時間の比べ方の筋書きの最後の段で測ることを求める11の操作である。
var PerfUses = []RequiredUse{
	requiredUse("ログイン", []UseStep{opStep("login")}),
	requiredUse("トークンの更新", []UseStep{opStep("refreshToken")}),
	requiredUse("利用者の情報の取得", []UseStep{opStep("getUserInfo")}),
	requiredUse("経歴書の一覧", []UseStep{opStep("listResumes")}),
	requiredUse("経歴書の取得", []UseStep{opStep("getResume")}),
	requiredUse("基本情報の保存", []UseStep{opStep("updateResumeBasic")}),
	requiredUse("職歴の追加", []UseStep{opStep("createCareer")}),
	requiredUse("PDF の出力", []UseStep{{Operations: exportOperations, Accept: "application/pdf"}}),
	requiredUse("Markdown の出力", []UseStep{{Operations: exportOperations, Accept: "text/markdown"}}),
	requiredUse("バックアップの書き出し", []UseStep{opStep("backupResume")}),
	requiredUse("バックアップの戻し", []UseStep{opStep("restoreResume")}),
}

// MissingCrossUses は、CrossUses のうち、版をまたぐ動かし方の筋書きに出てこない操作の名前を、CrossUses の順に返す。
// 段の Version は、CrossDirections のどれか1つの送り先の組で、CrossRoute がその段を送る版と比べる。
func MissingCrossUses(ops Operations, scenarios []Scenario) ([]string, error) {
	type routed struct {
		scenario Scenario
		route    []string
	}
	var candidates []routed
	for _, s := range scenarios {
		if !s.HasMode(ModeCross) {
			continue
		}
		for _, direction := range CrossDirections {
			route, err := CrossRoute(s, direction)
			if err != nil {
				return nil, err
			}
			candidates = append(candidates, routed{s, route})
		}
	}
	var missing []string
	for _, u := range CrossUses {
		found := func(seq []UseStep) bool {
			return slices.ContainsFunc(candidates, func(c routed) bool {
				return containsSequence(ops, c.scenario.Steps, c.route, seq)
			})
		}
		if !allSequences(u, found) {
			missing = append(missing, u.Name)
		}
	}
	return missing, nil
}

// MissingPerfUses は、PerfUses のうち、応答の時間の比べ方の筋書きの最後の段で測っていない操作の名前を、PerfUses の順に返す。
// 測るのは最後の段だけなので、段の並びの最後は筋書きの最後の段に当たり、それより前は準備の段に出てこなければならない。
func MissingPerfUses(ops Operations, scenarios []Scenario) []string {
	var missing []string
	for _, u := range PerfUses {
		found := func(seq []UseStep) bool {
			return slices.ContainsFunc(scenarios, func(s Scenario) bool {
				if !s.HasMode(ModePerf) || len(s.Steps) == 0 {
					return false
				}
				last := len(s.Steps) - 1
				return matchStep(ops, s.Steps[last], "", seq[len(seq)-1]) &&
					containsSequence(ops, s.Steps[:last], nil, seq[:len(seq)-1])
			})
		}
		if !allSequences(u, found) {
			missing = append(missing, u.Name)
		}
	}
	return missing
}

// allSequences は、u の段の並びが、すべて found に当たるかを返す。段の並びの無い操作は、当たらないとする。
func allSequences(u RequiredUse, found func([]UseStep) bool) bool {
	if len(u.Sequences) == 0 {
		return false
	}
	for _, seq := range u.Sequences {
		if !found(seq) {
			return false
		}
	}
	return true
}

// containsSequence は、段 steps に、seq の条件に当たる段がこの順で出てくるかを返す。route は段ごとに送る版で、nil なら版を見ない。
// 前から順に、最初に当たる段を選ぶ。どの条件も段1つで決まるので、早く当たる段を選んでも、あとの条件に当たる段は減らない。
func containsSequence(ops Operations, steps []Step, route []string, seq []UseStep) bool {
	next := 0
	for i, step := range steps {
		if next == len(seq) {
			break
		}
		version := ""
		if route != nil {
			version = route[i]
		}
		if matchStep(ops, step, version, seq[next]) {
			next++
		}
	}
	return next == len(seq)
}

// matchStep は、段 step が条件 want に当たるかを返す。version は、送り先の組がその段を送る版である。
func matchStep(ops Operations, step Step, version string, want UseStep) bool {
	if step.Kind() != StepVersion {
		return false
	}
	if !slices.Contains(want.Operations, ops.Lookup(step.Request.Method, step.Request.Path)) {
		return false
	}
	if want.Query != "" {
		_, query, _ := strings.Cut(step.Request.Path, "?")
		if !strings.Contains(query, want.Query) {
			return false
		}
	}
	if want.Accept != "" && !strings.Contains(headerValue(step.Request.Headers, "Accept"), want.Accept) {
		return false
	}
	return want.Version == "" || want.Version == version
}

// headerValue は、ヘッダの名前の大文字と小文字を区別せずに、headers から name の値を返す。
func headerValue(headers map[string]string, name string) string {
	for k, v := range headers {
		if strings.EqualFold(k, name) {
			return v
		}
	}
	return ""
}
