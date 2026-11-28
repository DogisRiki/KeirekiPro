package resume

import (
	"reflect"
	"testing"
	"time"
)

// TestExportModel_Formats は、出力のモデルの日付と期間の書き方と、作業の工程の並びと、技術スタックの並びと、
// 値の無い欄の扱いが、Java 版の ResumeExportModelBuilder と同じになることを確かめる。
func TestExportModel_Formats(t *testing.T) {
	ym := func(y int, m time.Month) YearMonth { return YearMonth{Year: y, Month: m} }
	active := func(y int, m time.Month) Period { return Period{StartDate: ym(y, m), Active: true} }
	ended := func(y int, m time.Month, ey int, em time.Month) Period {
		e := ym(ey, em)
		return Period{StartDate: ym(y, m), EndDate: &e}
	}

	t.Run("見出しと日付と氏名", func(t *testing.T) {
		cases := []struct {
			last, first *string
			want        string
		}{
			{ptr("田中"), ptr("次郎"), "田中 次郎"},
			{nil, ptr("次郎"), "次郎"},
			{ptr("田中"), nil, "田中"},
			{nil, nil, ""},
			{ptr(" 田中"), ptr("次郎\t"), "田中 次郎"},
		}
		for _, c := range cases {
			m := buildExportModel(Resume{Date: Date{Year: 2026, Month: time.February, Day: 6}, LastName: c.last, FirstName: c.first})
			if m.Title != "職務経歴書" || m.AsOfDateLabel != "2026年2月6日現在" || m.FullName != c.want {
				t.Errorf("見出し %q、日付 %q、氏名 %q。期待は 職務経歴書、2026年2月6日現在、%q", m.Title, m.AsOfDateLabel, m.FullName, c.want)
			}
		}
	})

	t.Run("職歴の期間", func(t *testing.T) {
		m := buildExportModel(Resume{Careers: []Career{
			{CompanyName: "A", Period: active(2020, time.April)},
			{CompanyName: "B", Period: ended(2015, time.April, 2019, time.March)},
			{CompanyName: "C", Period: Period{StartDate: ym(2012, time.November)}},
		}})
		want := []exportCareer{
			{PeriodLabel: "2020年4月 〜 現在", CompanyName: "A"},
			{PeriodLabel: "2015年4月 〜 2019年3月", CompanyName: "B"},
			{PeriodLabel: "2012年11月 〜 ", CompanyName: "C"},
		}
		if !reflect.DeepEqual(m.Careers, want) {
			t.Errorf("職歴 %#v。期待は %#v", m.Careers, want)
		}
	})

	t.Run("プロジェクトの期間と見出しと勤務先のまとまり", func(t *testing.T) {
		m := buildExportModel(Resume{
			Careers: []Career{
				{CompanyName: "X", Period: ended(2010, time.April, 2014, time.March)},
				{CompanyName: "X", Period: active(2020, time.April)},
				{CompanyName: "  ", Period: active(2021, time.April)},
			},
			Projects: []Project{
				{CompanyName: "X", Name: "P1", Period: active(2019, time.April), Overview: "o", TeamComp: "t", Role: "r"},
				{CompanyName: "Y", Name: "P2", Period: ended(2015, time.April, 2019, time.March)},
				{CompanyName: "X", Name: "P3", Period: Period{StartDate: ym(2011, time.May)}},
				{CompanyName: "  ", Name: "P4", Period: active(2021, time.May)},
			},
		})
		type got struct{ company, companyPeriod, label, start, end, name string }
		var gs []got
		for _, s := range m.CompanySections {
			for _, p := range s.Projects {
				gs = append(gs, got{s.CompanyLabel, s.CompanyPeriodLabel, p.ProjectLabel, p.PeriodStartLabel, p.PeriodEndLabel, p.ProjectName})
			}
		}
		want := []got{
			{"X", "2010年4月 〜 2014年3月", "P1（2019年4月 〜 現在）", "2019年4月", "現在", "P1"},
			{"X", "2010年4月 〜 2014年3月", "P3（2011年5月 〜 ）", "2011年5月", "", "P3"},
			{"Y", "", "P2（2015年4月 〜 2019年3月）", "2015年4月", "2019年3月", "P2"},
			{"  ", "", "P4（2021年5月 〜 現在）", "2021年5月", "現在", "P4"},
		}
		if len(m.CompanySections) != 3 || !reflect.DeepEqual(gs, want) {
			t.Errorf("勤務先のまとまり %d 件、%#v。期待は 3 件、%#v", len(m.CompanySections), gs, want)
		}
		p := m.CompanySections[0].Projects[0]
		if p.Overview != "o" || p.TeamComp != "t" || p.Role != "r" {
			t.Errorf("概要 %q、チーム構成 %q、役割 %q", p.Overview, p.TeamComp, p.Role)
		}
	})

	t.Run("作業の工程", func(t *testing.T) {
		cases := []struct {
			in   Process
			want string
		}{
			{Process{true, true, true, true, true, true, true}, "要件定義、基本設計、詳細設計、実装・単体テスト、結合テスト、総合テスト、運用・保守"},
			{Process{BasicDesign: true, Maintenance: true}, "基本設計、運用・保守"},
			{Process{Implementation: true}, "実装・単体テスト"},
			{Process{}, ""},
		}
		for _, c := range cases {
			got := buildExportProject(Project{Process: c.in}).Process
			want := exportProcess{
				Requirements: c.in.Requirements, BasicDesign: c.in.BasicDesign, DetailedDesign: c.in.DetailedDesign,
				Implementation: c.in.Implementation, IntegrationTest: c.in.IntegrationTest, SystemTest: c.in.SystemTest,
				Maintenance: c.in.Maintenance, Label: c.want,
			}
			if got != want {
				t.Errorf("工程 %#v。期待は %#v", got, want)
			}
		}
	})

	t.Run("成果の行", func(t *testing.T) {
		checkDiffTableInChangedBehaviors(t, map[string]string{"改行しない空白だけの成果の行": "CB-117", "箇条書きの記号のあとの制御の字と行の区切りの字": "CB-129"})
		cases := []struct {
			in   string
			want []string
		}{
			{"", nil},
			{" 　\t", nil},
			{"- a\r\n*  b\r• c\n・ d\n  \n　\n-\te \n-\n*x\n-\t\u2028f\n-\u2028g\nh", []string{"・a", "・b", "・c", "・ d", "・e", "-", "*x", "・\u2028f", "-\u2028g", "h"}},
			{"1行目\n\n2行目\n", []string{"1行目", "2行目"}},
			// 記号のあとの ASCII の制御の字は空白として除き、全角の空白のあとの記号は直さない(変えた動きの一覧の CB-129)。
			{"-\u0001a\n*　b\n•\u0085c", []string{"・a", "*　b", "•\u0085c"}},
			// 行の前後の ASCII の制御の字は除き、全角の空白は字下げとして残す。
			{"\u0001a\u001f\n　字下げの行\u3000", []string{"a", "　字下げの行\u3000"}},
			// 改行しない空白だけの行は、空白だけの行として除く(変えた動きの一覧の CB-117)。
			{"a\n\u00a0\n\u202f\nb", []string{"a", "b"}},
		}
		for _, c := range cases {
			got := buildExportProject(Project{Achievement: c.in}).Achievements
			if !reflect.DeepEqual(got, c.want) {
				t.Errorf("成果 %q を %#v に分けた。期待は %#v", c.in, got, c.want)
			}
		}
	})

	t.Run("技術スタックの並びの直し方", func(t *testing.T) {
		var ts TechStack
		ts.Frontend.Languages = []*string{ptr(" TypeScript "), nil, ptr("  "), ptr("TypeScript"), ptr("Go")}
		ts.Backend.Languages = []*string{}
		ts.Backend.Auth = []*string{nil, ptr("　")}
		ts.Tools.APIDevelopmentTools = []*string{ptr("Postman")}
		// 前後の空白を除くと空白だけになる名前は、Markdown には Java 版と同じく残し、PDF の行には出さない。
		ts.Infrastructure.Clouds = []*string{ptr("\u0001")}
		ts.Tools.Editors = []*string{ptr("\u0001　")}
		p := buildExportProject(Project{TechStack: ts})
		want := &exportTech{
			Frontend:       &FrontendStacks[string]{Languages: []string{"TypeScript", "Go"}},
			Infrastructure: &InfrastructureStacks[string]{Clouds: []string{""}},
			Tools:          &ToolStacks[string]{APIDevelopmentTools: []string{"Postman"}, Editors: []string{"　"}},
		}
		if !reflect.DeepEqual(p.Tech, want) {
			t.Errorf("Markdown の技術スタック %#v。期待は %#v", p.Tech, want)
		}
		wantSections := []exportTechSection{
			{Title: "フロントエンド", Lines: []exportTechLine{{Label: "開発言語", Value: "TypeScript、Go"}}},
			{Title: "開発支援ツール", Lines: []exportTechLine{{Label: "API開発", Value: "Postman"}}},
		}
		if !reflect.DeepEqual(p.TechSections, wantSections) {
			t.Errorf("PDF の技術スタック %#v。期待は %#v", p.TechSections, wantSections)
		}
		empty := buildExportProject(Project{})
		if empty.Tech != nil || empty.TechSections != nil {
			t.Errorf("名前の無い技術スタックが %#v と %#v になった。期待は両方とも値が無いこと", empty.Tech, empty.TechSections)
		}
	})

	t.Run("技術スタックの小分類の並び", func(t *testing.T) {
		var ts TechStack
		fillTechStack(reflect.ValueOf(&ts).Elem())
		p := buildExportProject(Project{TechStack: ts})
		tech := reflect.ValueOf(p.Tech).Elem()
		for i := range tech.NumField() {
			cat := tech.Field(i)
			if cat.IsNil() {
				t.Errorf("大分類 %s が無い", tech.Type().Field(i).Name)
				continue
			}
			cat = cat.Elem()
			for j := range cat.NumField() {
				name := cat.Type().Field(j).Name
				if got := cat.Field(j).Interface().([]string); !reflect.DeepEqual(got, []string{name}) {
					t.Errorf("%s の %s が %#v。期待は %q だけ", tech.Type().Field(i).Name, name, got, name)
				}
			}
		}
		want := []exportTechSection{
			{"フロントエンド", techLines("開発言語", "Languages", "フレームワーク", "Frameworks", "ライブラリ", "Libraries",
				"ビルドツール", "BuildTools", "パッケージマネージャー", "PackageManagers", "リンター", "Linters",
				"フォーマッター", "Formatters", "テストツール", "TestingTools")},
			{"バックエンド", techLines("開発言語", "Languages", "フレームワーク", "Frameworks", "ライブラリ", "Libraries",
				"ビルドツール", "BuildTools", "パッケージマネージャー", "PackageManagers", "リンター", "Linters",
				"フォーマッター", "Formatters", "テストツール", "TestingTools", "ORM", "OrmTools", "認証", "Auth")},
			{"インフラ", techLines("クラウド", "Clouds", "OS", "OperatingSystems", "コンテナ", "Containers",
				"データベース", "Databases", "Webサーバー", "WebServers", "CI/CD", "CiCdTools", "IaC", "IacTools",
				"監視", "MonitoringTools", "ロギング", "LoggingTools")},
			{"開発支援ツール", techLines("ソース管理", "SourceControls", "プロジェクト管理", "ProjectManagements",
				"コミュニケーション", "CommunicationTools", "ドキュメント", "DocumentationTools", "API開発", "APIDevelopmentTools",
				"デザイン", "DesignTools", "エディタ", "Editors", "開発環境", "DevelopmentEnvironments")},
		}
		if !reflect.DeepEqual(p.TechSections, want) {
			t.Errorf("PDF の技術スタック %#v。期待は %#v", p.TechSections, want)
		}
	})

	t.Run("資格とポートフォリオとSNSと自己PR", func(t *testing.T) {
		m := buildExportModel(Resume{
			Certifications: []Certification{{Name: "応用情報", Date: ym(2014, time.June)}, {Name: "基本情報", Date: ym(2012, time.November)}},
			Portfolios: []Portfolio{
				{Name: "A", Overview: "o", TechStack: ptr("Go、AWS"), Link: "https://example.com/a"},
				{Name: "B", Overview: "p", Link: "https://example.com/b"},
			},
			SnsPlatforms:   []SnsPlatform{{Name: "GitHub", Link: "https://github.com/x"}},
			SelfPromotions: []SelfPromotion{{Title: "T", Content: "C\nD"}},
		})
		wantCerts := []exportCertification{{AcquiredAtLabel: "2014年6月", Name: "応用情報"}, {AcquiredAtLabel: "2012年11月", Name: "基本情報"}}
		wantPortfolios := []exportPortfolio{
			{Name: "A", URL: "https://example.com/a", TechStack: ptr("Go、AWS"), Overview: "o"},
			{Name: "B", URL: "https://example.com/b", Overview: "p"},
		}
		wantSns := []exportSnsPlatform{{Name: "GitHub", URL: "https://github.com/x"}}
		wantSelf := []exportSelfPromotion{{Title: "T", Content: "C\nD"}}
		if !reflect.DeepEqual(m.Certifications, wantCerts) || !reflect.DeepEqual(m.Portfolios, wantPortfolios) ||
			!reflect.DeepEqual(m.SnsPlatforms, wantSns) || !reflect.DeepEqual(m.SelfPromotions, wantSelf) {
			t.Errorf("資格 %#v、ポートフォリオ %#v、SNS %#v、自己PR %#v", m.Certifications, m.Portfolios, m.SnsPlatforms, m.SelfPromotions)
		}
		none := buildExportModel(Resume{})
		if none.Careers != nil || none.CompanySections != nil || none.Certifications != nil || none.Portfolios != nil ||
			none.SnsPlatforms != nil || none.SelfPromotions != nil {
			t.Errorf("項目の無い経歴書のモデル %#v", none)
		}
	})
}

// fillTechStack は、技術スタックのすべての小分類に、小分類の名前を1つだけ入れる。
func fillTechStack(v reflect.Value) {
	for i := range v.NumField() {
		cat := v.Field(i)
		for j := range cat.NumField() {
			name := cat.Type().Field(j).Name
			cat.Field(j).Set(reflect.ValueOf([]*string{&name}))
		}
	}
}

// techLines は、小分類の名前と値の組を、PDF の技術スタックの行にする。
func techLines(pairs ...string) []exportTechLine {
	var lines []exportTechLine
	for i := 0; i+1 < len(pairs); i += 2 {
		lines = append(lines, exportTechLine{Label: pairs[i], Value: pairs[i+1]})
	}
	return lines
}
