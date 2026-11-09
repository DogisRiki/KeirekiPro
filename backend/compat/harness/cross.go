//go:build compat

package harness

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"
)

// 版をまたぐ動かし方で試す、3つの送り先の組である。
const (
	// CrossJavaToGo は、1つ目の段を Java 版に送り、to: other の段で Go 版へ移る組である。
	CrossJavaToGo = "java-to-go"
	// CrossGoToJava は、1つ目の段を Go 版に送り、to: other の段で Java 版へ移る組である。
	CrossGoToJava = "go-to-java"
	// CrossAlternate は、筋書きの to によらず、1つ目の段を Java 版に送り、段ごとに2つの版へ交互に送る組である。
	CrossAlternate = "alternate"
)

// CrossDirections は、版をまたぐ動かし方が筋書きごとに試す、3つの送り先の組である。
var CrossDirections = []string{CrossJavaToGo, CrossGoToJava, CrossAlternate}

// other は、もう一方の版の名前を返す。
func other(version string) string {
	if version == VersionJava {
		return VersionGo
	}
	return VersionJava
}

// CrossRoute は、送り先の組 direction で、筋書きの段ごとに送る版の名前を返す。
// 最後の段は、筋書きの to によらず、その前の段と違う版に送る。片方の版が保存した内容を、もう一方の版から読んで、
// 消えていないことを確かめるためである。筋書きの最後の段には、保存した内容を読む要求を書く。
func CrossRoute(s Scenario, direction string) ([]string, error) {
	if len(s.Steps) < 2 {
		return nil, fmt.Errorf("harness: 筋書き %s は、版をまたぐために2つ以上の段が要りますが、%d 段です", s.Name, len(s.Steps))
	}
	route := make([]string, len(s.Steps))
	switch direction {
	case CrossJavaToGo, CrossGoToJava:
		route[0] = VersionJava
		if direction == CrossGoToJava {
			route[0] = VersionGo
		}
		for i := 1; i < len(s.Steps); i++ {
			route[i] = route[i-1]
			if s.Steps[i].To == ToOther {
				route[i] = other(route[i-1])
			}
		}
	case CrossAlternate:
		for i := range s.Steps {
			route[i] = VersionJava
			if i%2 == 1 {
				route[i] = VersionGo
			}
		}
	default:
		return nil, fmt.Errorf("harness: 送り先の組 %q は %v のどれでもありません", direction, CrossDirections)
	}
	last := len(route) - 1
	route[last] = other(route[last-1])
	return route, nil
}

// CrossFailure は、版をまたぐ動かし方で、1つの送り先の組が最後まで終わらなかった段である。
type CrossFailure struct {
	Direction string
	// Step は、終わらなかった段である。Index は1から数える。段に進む前の準備で失敗したときは、Index を0にする。
	Step StepRef
	// Version は、段を送った版の名前である。
	Version string
	// Problems は、段の応答が期待に合わなかったことか、段を送れなかった理由である。
	Problems []string
}

// CrossReport は、1つの筋書きの、版をまたぐ動かし方の報告である。
type CrossReport struct {
	Scenario string
	// Directions は、試した送り先の組である。
	Directions []string
	// Failures は、送り先の組ごとの、最後まで終わらなかった段である。1つの組の中では、最初に失敗した段で止める。
	Failures []CrossFailure
}

// Failed は、最後まで終わらなかった送り先の組があるかを返す。
func (r CrossReport) Failed() bool {
	return len(r.Failures) > 0
}

// String は、報告を、人が読む文にする。失敗ごとに、筋書きの名前、送り先の組、段、送った版、期待と違ったことを書く。
func (r CrossReport) String() string {
	var b strings.Builder
	fmt.Fprintf(&b, "筋書き: %s(版をまたぐ確認)\n", r.Scenario)
	fmt.Fprintf(&b, "試した送り先の組: %s\n", strings.Join(r.Directions, "、"))
	if !r.Failed() {
		b.WriteString("最後まで終わらなかった組: 0 件\n")
		return b.String()
	}
	fmt.Fprintf(&b, "最後まで終わらなかった組: %d 件\n", len(r.Failures))
	for i, f := range r.Failures {
		step := "段に進む前の準備"
		if f.Step.Index > 0 {
			step = describeStep(f.Step)
		}
		fmt.Fprintf(&b, "\n[%d] 筋書き: %s / 送り先の組: %s / 段: %s", i+1, r.Scenario, f.Direction, step)
		if f.Version != "" {
			fmt.Fprintf(&b, " / 送った版: %s", f.Version)
		}
		b.WriteString("\n")
		for _, p := range f.Problems {
			writeValue(&b, "期待と違ったこと", p)
		}
	}
	return b.String()
}

// Write は、報告を dir の cross-<筋書きの名前>.txt に書き、書いたファイルのパスを返す。
func (r CrossReport) Write(dir string) (string, error) {
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return "", fmt.Errorf("harness: 報告のフォルダ %s を作れません: %w", dir, err)
	}
	name := unsafeFileChars.ReplaceAllString(r.Scenario, "_")
	if name == "" || strings.Trim(name, ".") == "" {
		name = "scenario"
	}
	file := filepath.Join(dir, "cross-"+name+".txt")
	if err := os.WriteFile(file, []byte(r.String()), 0o600); err != nil {
		return "", fmt.Errorf("harness: 報告 %s を書けません: %w", file, err)
	}
	return file, nil
}

// RunCross は、送り先の組 direction で、筋書きの段を順に、CrossRoute が決めた版へ送る。
// urls は、版の名前ごとの、テストの処理から届く URL である。2つの版に1つの Session を使い、Cookie と取り出した値を引き継ぐ。
// 応答は比べず、各段の応答が expect に合うかを確かめる。合わない段があれば、その段の失敗を返し、残りの段は送らない。
// 後の段は前の段の結果を前提にするので、続けても意味のある確かめにならないためである。
func RunCross(ctx context.Context, client *http.Client, s Scenario, direction string, urls map[string]string) *CrossFailure {
	route, err := CrossRoute(s, direction)
	if err != nil {
		return &CrossFailure{Direction: direction, Problems: []string{err.Error()}}
	}
	session := NewSession()
	for i, step := range s.Steps {
		version := route[i]
		ref := StepRef{Index: i + 1, Name: step.Name}
		baseURL, ok := urls[version]
		if !ok {
			return &CrossFailure{Direction: direction, Step: ref, Version: version, Problems: []string{"版 " + version + " の URL がありません"}}
		}
		resp, err := session.Send(ctx, client, baseURL, step)
		problems := CheckExpect(step, resp)
		if err != nil {
			problems = append(problems, err.Error())
		}
		if len(problems) > 0 {
			if resp.Status != 0 {
				problems = append(problems, "応答の本文: "+describeBody(resp.Body))
			}
			return &CrossFailure{Direction: direction, Step: ref, Version: version, Problems: problems}
		}
	}
	return nil
}

// describeBody は、期待に合わなかった段の応答の本文を、報告に書く形にする。
// 短い文字の本文は、失敗の理由が読めるように、そのまま書く。長い本文と文字でない本文(PDF など)は、大きさと SHA-256 にする。
func describeBody(b []byte) string {
	const limit = 2000
	if len(b) <= limit && utf8.Valid(b) {
		return string(b)
	}
	return describeBytes(b)
}
