package resume

import (
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// exportTitle は、2つのひな形の見出しである。
const exportTitle = "職務経歴書"

// exportModel は、Markdown と PDF のひな形が読む値である。Java 版の ResumeExportModelBuilder が作るモデルを写した。
// 値の名前は、Java 版のモデルの鍵の頭を大文字にしたものである。
type exportModel struct {
	Title           string
	AsOfDateLabel   string
	FullName        string
	Careers         []exportCareer
	CompanySections []exportCompanySection
	Certifications  []exportCertification
	Portfolios      []exportPortfolio
	SnsPlatforms    []exportSnsPlatform
	SelfPromotions  []exportSelfPromotion
}

// exportCareer は、職歴の欄の1行である。
type exportCareer struct {
	PeriodLabel string
	CompanyName string
}

// exportCompanySection は、職務内容の欄の、勤務先ごとのまとまりである。
type exportCompanySection struct {
	CompanyLabel       string
	CompanyPeriodLabel string
	Projects           []exportProject
}

// exportProject は、職務内容の欄の、プロジェクトごとのまとまりである。
type exportProject struct {
	PeriodStartLabel string
	PeriodEndLabel   string
	ProjectLabel     string
	ProjectName      string
	Overview         string
	TeamComp         string
	Role             string
	Achievements     []string
	Process          exportProcess
	// Tech は、Markdown が読む技術スタックである。書ける値が1つも無いとき nil にする。
	Tech *exportTech
	// TechSections は、PDF が読む技術スタックである。
	TechSections []exportTechSection
}

// exportProcess は、プロジェクトの作業の工程である。Label は、行う工程の名前を「、」でつないだものである。
type exportProcess struct {
	Requirements    bool
	BasicDesign     bool
	DetailedDesign  bool
	Implementation  bool
	IntegrationTest bool
	SystemTest      bool
	Maintenance     bool
	Label           string
}

// exportTech は、Markdown が読む技術スタックである。書ける値が1つも無い大分類を nil にする。
// 小分類の並びは、空白だけの名前を除き、前後の空白を除き、重なりを除いたものであり、残らなければ nil にする。
type exportTech struct {
	Frontend       *FrontendStacks[string]
	Backend        *BackendStacks[string]
	Infrastructure *InfrastructureStacks[string]
	Tools          *ToolStacks[string]
}

// exportTechSection は、PDF が読む技術スタックの大分類である。
type exportTechSection struct {
	Title string
	Lines []exportTechLine
}

// exportTechLine は、PDF が読む技術スタックの小分類の1行である。Value は、名前を「、」でつないだものである。
type exportTechLine struct {
	Label string
	Value string
}

// exportCertification は、資格の欄の1行である。
type exportCertification struct {
	AcquiredAtLabel string
	Name            string
}

// exportPortfolio は、ポートフォリオの欄の1件である。
type exportPortfolio struct {
	Name      string
	URL       string
	TechStack *string
	Overview  string
}

// exportSnsPlatform は、SNS の欄の1行である。
type exportSnsPlatform struct {
	Name string
	URL  string
}

// exportSelfPromotion は、自己PR の欄の1件である。
type exportSelfPromotion struct {
	Title   string
	Content string
}

// buildExportModel は、経歴書から出力のモデルを作る。Java 版の ResumeExportModelBuilder.build を写した。
func buildExportModel(r Resume) exportModel {
	m := exportModel{
		Title:         exportTitle,
		AsOfDateLabel: fmt.Sprintf("%d年%d月%d日現在", r.Date.Year, int(r.Date.Month), r.Date.Day),
		FullName:      formatExportFullName(r.LastName, r.FirstName),
	}
	for _, c := range r.Careers {
		m.Careers = append(m.Careers, exportCareer{PeriodLabel: formatExportPeriod(c.Period), CompanyName: c.CompanyName})
	}
	index := map[string]int{}
	for _, p := range r.Projects {
		i, ok := index[p.CompanyName]
		if !ok {
			i = len(m.CompanySections)
			index[p.CompanyName] = i
			m.CompanySections = append(m.CompanySections, exportCompanySection{
				CompanyLabel:       p.CompanyName,
				CompanyPeriodLabel: companyPeriodLabel(p.CompanyName, r.Careers),
			})
		}
		m.CompanySections[i].Projects = append(m.CompanySections[i].Projects, buildExportProject(p))
	}
	for _, c := range r.Certifications {
		m.Certifications = append(m.Certifications, exportCertification{AcquiredAtLabel: formatExportYearMonth(&c.Date), Name: c.Name})
	}
	for _, p := range r.Portfolios {
		m.Portfolios = append(m.Portfolios, exportPortfolio{Name: p.Name, URL: p.Link, TechStack: p.TechStack, Overview: p.Overview})
	}
	for _, s := range r.SnsPlatforms {
		m.SnsPlatforms = append(m.SnsPlatforms, exportSnsPlatform{Name: s.Name, URL: s.Link})
	}
	for _, s := range r.SelfPromotions {
		m.SelfPromotions = append(m.SelfPromotions, exportSelfPromotion{Title: s.Title, Content: s.Content})
	}
	return m
}

// buildExportProject は、プロジェクトの1件を出力のモデルにする。
func buildExportProject(p Project) exportProject {
	return exportProject{
		PeriodStartLabel: formatExportYearMonth(&p.Period.StartDate),
		PeriodEndLabel:   formatExportPeriodEnd(p.Period),
		ProjectLabel:     p.Name + "（" + formatExportPeriod(p.Period) + "）",
		ProjectName:      p.Name,
		Overview:         p.Overview,
		TeamComp:         p.TeamComp,
		Role:             p.Role,
		Achievements:     splitAchievementLines(p.Achievement),
		Process:          buildExportProcess(p.Process),
		Tech:             buildExportTech(p.TechStack),
		TechSections:     buildExportTechSections(p.TechStack),
	}
}

// companyPeriodLabel は、勤務先の名前と同じ名前の最初の職歴の期間を返す。勤務先の名前が空白だけのときと、
// 同じ名前の職歴が無いときは、空の文字列を返す。
func companyPeriodLabel(company string, careers []Career) string {
	if !auth.NotBlank(company) {
		return ""
	}
	for _, c := range careers {
		if c.CompanyName == company {
			return formatExportPeriod(c.Period)
		}
	}
	return ""
}

// javaTrim は、Java の String.trim と同じく、前後の U+0020 以下の字を除く。
func javaTrim(s string) string {
	return strings.TrimFunc(s, func(r rune) bool { return r <= ' ' })
}

// formatExportFullName は、氏名を「姓 名」の形にする。値の無い姓と名は空の文字列とし、前後の空白を除く。
func formatExportFullName(last, first *string) string {
	l, f := "", ""
	if last != nil {
		l = *last
	}
	if first != nil {
		f = *first
	}
	return javaTrim(l + " " + f)
}

// formatExportYearMonth は、年月を「2006年1月」の形にする。値が無いときは空の文字列を返す。
func formatExportYearMonth(y *YearMonth) string {
	if y == nil {
		return ""
	}
	return fmt.Sprintf("%d年%d月", y.Year, int(y.Month))
}

// formatExportPeriod は、期間を「開始年月 〜 終了年月」か「開始年月 〜 現在」の形にする。
func formatExportPeriod(p Period) string {
	start := formatExportYearMonth(&p.StartDate)
	if p.Active {
		return start + " 〜 現在"
	}
	return start + " 〜 " + formatExportYearMonth(p.EndDate)
}

// formatExportPeriodEnd は、期間の終わりを、継続中なら「現在」に、それ以外は終了年月にする。
func formatExportPeriodEnd(p Period) string {
	if p.Active {
		return "現在"
	}
	return formatExportYearMonth(p.EndDate)
}

// exportProcessLabels は、作業の工程の名前である。並びは、Java 版の formatProcess の順である。
var exportProcessLabels = [7]string{"要件定義", "基本設計", "詳細設計", "実装・単体テスト", "結合テスト", "総合テスト", "運用・保守"}

// buildExportProcess は、作業の工程を出力のモデルにする。
func buildExportProcess(p Process) exportProcess {
	flags := [7]bool{p.Requirements, p.BasicDesign, p.DetailedDesign, p.Implementation, p.IntegrationTest, p.SystemTest, p.Maintenance}
	var labels []string
	for i, on := range flags {
		if on {
			labels = append(labels, exportProcessLabels[i])
		}
	}
	return exportProcess{
		Requirements:    p.Requirements,
		BasicDesign:     p.BasicDesign,
		DetailedDesign:  p.DetailedDesign,
		Implementation:  p.Implementation,
		IntegrationTest: p.IntegrationTest,
		SystemTest:      p.SystemTest,
		Maintenance:     p.Maintenance,
		Label:           strings.Join(labels, "、"),
	}
}

// splitAchievementLines は、成果の文を行に分ける。Java 版の splitLines を写した。
// 行の区切りは、Java の String.lines と同じく \r\n と \r と \n である。行ごとに前後の空白を除き、
// 頭の「- 」「* 」「• 」などを「・」に直し、空白だけの行を除く。
func splitAchievementLines(raw string) []string {
	if !auth.NotBlank(raw) {
		return nil
	}
	var lines []string
	for _, l := range strings.Split(strings.ReplaceAll(strings.ReplaceAll(raw, "\r\n", "\n"), "\r", "\n"), "\n") {
		l = normalizeBulletPrefix(javaTrim(l))
		if auth.NotBlank(l) {
			lines = append(lines, l)
		}
	}
	return lines
}

// normalizeBulletPrefix は、行の頭の箇条書きの記号を「・」に直す。Java 版の normalizeBulletPrefix を写した。
func normalizeBulletPrefix(s string) string {
	if strings.HasPrefix(s, "・") {
		return s
	}
	for _, p := range []string{"- ", "* ", "• "} {
		if rest, ok := strings.CutPrefix(s, p); ok {
			return "・" + javaTrim(rest)
		}
	}
	if rest, ok := cutBulletPattern(s); ok {
		return "・" + javaTrim(rest)
	}
	return s
}

// cutBulletPattern は、Java の正規表現 ^[\-\*•]\s+.*$ が s の全体に当たるとき、頭の記号と空白を除いた残りを返す。
// \s は Java の既定の範囲(空白、\t、\n、\v、\f、\r)である。. は行の区切りの字(\n、\r、U+0085、U+2028、U+2029)に当たらない。
func cutBulletPattern(s string) (string, bool) {
	r, size := utf8.DecodeRuneInString(s)
	if r != '-' && r != '*' && r != '•' {
		return "", false
	}
	body := s[size:]
	rest := strings.TrimLeft(body, " \t\n\v\f\r")
	if len(rest) == len(body) || strings.ContainsAny(rest, "\n\r\u0085  ") {
		return "", false
	}
	return rest, true
}

// normalizeExportList は、技術スタックの名前の並びから、値の無い名前と空白だけの名前を除き、前後の空白を除き、
// 重なりを除く。Java 版の normalizeList を写した。残らなければ nil を返す。
func normalizeExportList(values []*string) []string {
	var out []string
	seen := map[string]bool{}
	for _, v := range values {
		if v == nil || !auth.NotBlank(*v) {
			continue
		}
		s := javaTrim(*v)
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}

// anyExportList は、並びのどれかに名前があるかを返す。
func anyExportList(lists ...[]string) bool {
	for _, l := range lists {
		if len(l) > 0 {
			return true
		}
	}
	return false
}

// buildExportTech は、Markdown が読む技術スタックを作る。Java 版の buildTechModel を写した。
func buildExportTech(ts TechStack) *exportTech {
	n := normalizeExportList
	t := &exportTech{}
	fe := FrontendStacks[string]{
		Languages: n(ts.Frontend.Languages), Frameworks: n(ts.Frontend.Frameworks), Libraries: n(ts.Frontend.Libraries),
		BuildTools: n(ts.Frontend.BuildTools), PackageManagers: n(ts.Frontend.PackageManagers), Linters: n(ts.Frontend.Linters),
		Formatters: n(ts.Frontend.Formatters), TestingTools: n(ts.Frontend.TestingTools),
	}
	if anyExportList(fe.Languages, fe.Frameworks, fe.Libraries, fe.BuildTools, fe.PackageManagers, fe.Linters, fe.Formatters, fe.TestingTools) {
		t.Frontend = &fe
	}
	be := BackendStacks[string]{
		Languages: n(ts.Backend.Languages), Frameworks: n(ts.Backend.Frameworks), Libraries: n(ts.Backend.Libraries),
		BuildTools: n(ts.Backend.BuildTools), PackageManagers: n(ts.Backend.PackageManagers), Linters: n(ts.Backend.Linters),
		Formatters: n(ts.Backend.Formatters), TestingTools: n(ts.Backend.TestingTools), OrmTools: n(ts.Backend.OrmTools),
		Auth: n(ts.Backend.Auth),
	}
	if anyExportList(be.Languages, be.Frameworks, be.Libraries, be.BuildTools, be.PackageManagers, be.Linters, be.Formatters, be.TestingTools, be.OrmTools, be.Auth) {
		t.Backend = &be
	}
	in := InfrastructureStacks[string]{
		Clouds: n(ts.Infrastructure.Clouds), OperatingSystems: n(ts.Infrastructure.OperatingSystems),
		Containers: n(ts.Infrastructure.Containers), Databases: n(ts.Infrastructure.Databases),
		WebServers: n(ts.Infrastructure.WebServers), CiCdTools: n(ts.Infrastructure.CiCdTools),
		IacTools: n(ts.Infrastructure.IacTools), MonitoringTools: n(ts.Infrastructure.MonitoringTools),
		LoggingTools: n(ts.Infrastructure.LoggingTools),
	}
	if anyExportList(in.Clouds, in.OperatingSystems, in.Containers, in.Databases, in.WebServers, in.CiCdTools, in.IacTools, in.MonitoringTools, in.LoggingTools) {
		t.Infrastructure = &in
	}
	to := ToolStacks[string]{
		SourceControls: n(ts.Tools.SourceControls), ProjectManagements: n(ts.Tools.ProjectManagements),
		CommunicationTools: n(ts.Tools.CommunicationTools), DocumentationTools: n(ts.Tools.DocumentationTools),
		APIDevelopmentTools: n(ts.Tools.APIDevelopmentTools), DesignTools: n(ts.Tools.DesignTools),
		Editors: n(ts.Tools.Editors), DevelopmentEnvironments: n(ts.Tools.DevelopmentEnvironments),
	}
	if anyExportList(to.SourceControls, to.ProjectManagements, to.CommunicationTools, to.DocumentationTools, to.APIDevelopmentTools, to.DesignTools, to.Editors, to.DevelopmentEnvironments) {
		t.Tools = &to
	}
	if t.Frontend == nil && t.Backend == nil && t.Infrastructure == nil && t.Tools == nil {
		return nil
	}
	return t
}

// exportTechInput は、PDF の技術スタックの小分類の名前と、名前の並びの組である。
type exportTechInput struct {
	label  string
	values []*string
}

// buildExportTechSections は、PDF が読む技術スタックを作る。Java 版の buildTechSections を写した。
// 名前の無い小分類の行と、行の無い大分類を出さない。
func buildExportTechSections(ts TechStack) []exportTechSection {
	fe, be, in, to := ts.Frontend, ts.Backend, ts.Infrastructure, ts.Tools
	groups := []struct {
		title  string
		inputs []exportTechInput
	}{
		{"フロントエンド", []exportTechInput{
			{"開発言語", fe.Languages},
			{"フレームワーク", fe.Frameworks},
			{"ライブラリ", fe.Libraries},
			{"ビルドツール", fe.BuildTools},
			{"パッケージマネージャー", fe.PackageManagers},
			{"リンター", fe.Linters},
			{"フォーマッター", fe.Formatters},
			{"テストツール", fe.TestingTools},
		}},
		{"バックエンド", []exportTechInput{
			{"開発言語", be.Languages},
			{"フレームワーク", be.Frameworks},
			{"ライブラリ", be.Libraries},
			{"ビルドツール", be.BuildTools},
			{"パッケージマネージャー", be.PackageManagers},
			{"リンター", be.Linters},
			{"フォーマッター", be.Formatters},
			{"テストツール", be.TestingTools},
			{"ORM", be.OrmTools},
			{"認証", be.Auth},
		}},
		{"インフラ", []exportTechInput{
			{"クラウド", in.Clouds},
			{"OS", in.OperatingSystems},
			{"コンテナ", in.Containers},
			{"データベース", in.Databases},
			{"Webサーバー", in.WebServers},
			{"CI/CD", in.CiCdTools},
			{"IaC", in.IacTools},
			{"監視", in.MonitoringTools},
			{"ロギング", in.LoggingTools},
		}},
		{"開発支援ツール", []exportTechInput{
			{"ソース管理", to.SourceControls},
			{"プロジェクト管理", to.ProjectManagements},
			{"コミュニケーション", to.CommunicationTools},
			{"ドキュメント", to.DocumentationTools},
			{"API開発", to.APIDevelopmentTools},
			{"デザイン", to.DesignTools},
			{"エディタ", to.Editors},
			{"開発環境", to.DevelopmentEnvironments},
		}},
	}
	var sections []exportTechSection
	for _, g := range groups {
		var lines []exportTechLine
		for _, in := range g.inputs {
			// Java 版の putTechLine と同じく、整えた並びをつないだ値が空白だけなら、行を出さない。
			// 前後の空白を除くと空になる名前 "\u0001" は、整えた並びに "" として残るためである。
			if v := normalizeExportList(in.values); v != nil {
				if joined := strings.Join(v, "、"); auth.NotBlank(joined) {
					lines = append(lines, exportTechLine{Label: in.label, Value: joined})
				}
			}
		}
		if lines != nil {
			sections = append(sections, exportTechSection{Title: g.title, Lines: lines})
		}
	}
	return sections
}
