package resume

import (
	"strings"
	"testing"
)

// Java 版の ResumeExportRuleCheckService の8つの文言と、ExportResumeUseCase の2つの始まりの文である。
// テストは、実装の定数を使わずに、Java 版の文字列を写した値と比べる。
const (
	wantRuleName           = "職務経歴書名を入力してください。"
	wantRuleDate           = "日付を設定してください。"
	wantRuleFullName       = "氏名（姓・名）を入力してください。"
	wantRuleLastName       = "姓を入力してください。"
	wantRuleFirstName      = "名を入力してください。"
	wantRuleCareers        = "職歴を1件以上登録してください。"
	wantRuleProjects       = "プロジェクトを1件以上登録してください。"
	wantRuleSelfPromotions = "自己PRを1件以上登録してください。"
	wantLeadPreview        = "入力エラーがあるため、PDFプレビューを表示できません。"
	wantLeadExport         = "職務経歴書をエクスポートできません。"
)

// exportReadyResume は、出力の前提を満たす経歴書を返す。
func exportReadyResume() *Resume {
	last, first := "山田", "太郎"
	return &Resume{
		Name:           "職務経歴書",
		Date:           Date{Year: 2026, Month: 11, Day: 23},
		LastName:       &last,
		FirstName:      &first,
		Careers:        []Career{{}},
		Projects:       []Project{{}},
		SelfPromotions: []SelfPromotion{{}},
	}
}

// ruleError は、始まりの文 lead と足りないものの文言 missing から、Java 版と同じ誤りの文言を作る。
func ruleError(lead string, missing ...string) string {
	return lead + "\n- " + strings.Join(missing, "\n- ")
}

// TestExportRule_EachMissing は、8つの足りないもののそれぞれと、すべてが足りないときに、
// Java 版の ResumeExportRuleCheckService と同じ文言が同じ順に並ぶことを確かめる(要件3の受入基準2)。
func TestExportRule_EachMissing(t *testing.T) {
	blank := " \t　"
	cases := []struct {
		name   string
		change func(r *Resume)
		target func(r *exportRuleTarget)
		want   []string
	}{
		{name: "前提を満たす", want: nil},
		{name: "経歴書の名前が空", change: func(r *Resume) { r.Name = "" }, want: []string{wantRuleName}},
		{name: "経歴書の名前が空白だけ", change: func(r *Resume) { r.Name = blank }, want: []string{wantRuleName}},
		{name: "日付が無い", target: func(r *exportRuleTarget) { r.hasDate = false }, want: []string{wantRuleDate}},
		{name: "日付が無い経歴書", change: func(r *Resume) { r.Date = Date{} }, want: []string{wantRuleDate}},
		{name: "氏名が無い", target: func(r *exportRuleTarget) { r.fullName = nil }, want: []string{wantRuleFullName}},
		{name: "姓が無い", change: func(r *Resume) { r.LastName = nil }, want: []string{wantRuleLastName}},
		{name: "姓が空白だけ", change: func(r *Resume) { r.LastName = &blank }, want: []string{wantRuleLastName}},
		{name: "名が無い", change: func(r *Resume) { r.FirstName = nil }, want: []string{wantRuleFirstName}},
		{name: "名が空白だけ", change: func(r *Resume) { r.FirstName = &blank }, want: []string{wantRuleFirstName}},
		{name: "職歴が無い", change: func(r *Resume) { r.Careers = nil }, want: []string{wantRuleCareers}},
		{name: "プロジェクトが無い", change: func(r *Resume) { r.Projects = []Project{} }, want: []string{wantRuleProjects}},
		{name: "自己PRが無い", change: func(r *Resume) { r.SelfPromotions = nil }, want: []string{wantRuleSelfPromotions}},
		{
			// Java 版のデータベースから読んだ経歴書は、姓と名が NULL でも氏名を持つので、氏名の文言ではなく姓と名の文言になる
			name: "姓と名が無い経歴書", change: func(r *Resume) { r.LastName, r.FirstName = nil, nil },
			want: []string{wantRuleLastName, wantRuleFirstName},
		},
		{
			name: "氏名を持たずにすべてが足りない",
			change: func(r *Resume) {
				*r = Resume{}
			},
			target: func(r *exportRuleTarget) { r.fullName = nil },
			want:   []string{wantRuleName, wantRuleDate, wantRuleFullName, wantRuleCareers, wantRuleProjects, wantRuleSelfPromotions},
		},
		{
			name:   "氏名を持ってすべてが足りない",
			change: func(r *Resume) { *r = Resume{} },
			want:   []string{wantRuleName, wantRuleDate, wantRuleLastName, wantRuleFirstName, wantRuleCareers, wantRuleProjects, wantRuleSelfPromotions},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r := exportReadyResume()
			if c.change != nil {
				c.change(r)
			}
			target := exportRuleTargetOf(r)
			if c.target != nil {
				c.target(&target)
			}
			got := target.missing()
			if strings.Join(got, "|") != strings.Join(c.want, "|") {
				t.Errorf("足りないものの文言が %q、期待は %q", got, c.want)
			}
		})
	}
}

// TestExportRule_LeadingSentence は、出力の前提を満たさない経歴書の誤りの文言が、inline では PDF のプレビューの文で、
// attachment と設定を付けない出力では出力できない文で始まり、足りないものごとに改行と「- 」と文言が続くことを確かめる
// (要件3の受入基準2)。前提を満たす経歴書には誤りを返さないことも確かめる。
func TestExportRule_LeadingSentence(t *testing.T) {
	noCareers := exportReadyResume()
	noCareers.Careers = nil
	noCareers.SelfPromotions = nil
	cases := []struct {
		name   string
		resume *Resume
		inline bool
		want   string
	}{
		{name: "inline", resume: noCareers, inline: true, want: ruleError(wantLeadPreview, wantRuleCareers, wantRuleSelfPromotions)},
		{name: "attachment", resume: noCareers, inline: false, want: ruleError(wantLeadExport, wantRuleCareers, wantRuleSelfPromotions)},
		// 設定を付けない出力は、Java 版と同じく attachment として確かめる
		{name: "設定を付けない出力", resume: noCareers, want: ruleError(wantLeadExport, wantRuleCareers, wantRuleSelfPromotions)},
		{name: "前提を満たす inline", resume: exportReadyResume(), inline: true, want: ""},
		{name: "前提を満たす attachment", resume: exportReadyResume(), inline: false, want: ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			checkBusinessError(t, c.name, checkExportRule(c.resume, c.inline), c.want)
		})
	}
}
