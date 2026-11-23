package resume

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"testing"
	"text/template"
)

// TestRenderMarkdown_Escapes は、Markdown に出すすべての値で、利用者が書いた < > & " ' を、
// Java 版の Thymeleaf と同じく &lt; &gt; &amp; &quot; &#39; に書き換えることを確かめる。
func TestRenderMarkdown_Escapes(t *testing.T) {
	const raw = `<a&b>"c'`
	const escaped = `&lt;a&amp;b&gt;&quot;c&#39;`
	v := func(s string) string { return raw + s }
	tech := []string{v("1"), v("2")}
	m := exportModel{
		Title: v("title"), AsOfDateLabel: v("date"), FullName: v("name"),
		Careers: []exportCareer{{PeriodLabel: v("period"), CompanyName: v("company")}},
		CompanySections: []exportCompanySection{{
			CompanyLabel: v("label"),
			Projects: []exportProject{{
				ProjectLabel: v("project"), Overview: v("overview"), TeamComp: v("team"), Role: v("role"),
				Achievements: []string{v("a1"), v("a2")},
				Tech: &exportTech{
					Frontend:       &FrontendStacks[string]{Languages: tech},
					Backend:        &BackendStacks[string]{Auth: tech},
					Infrastructure: &InfrastructureStacks[string]{LoggingTools: tech},
					Tools:          &ToolStacks[string]{APIDevelopmentTools: tech},
				},
			}},
		}},
		Certifications: []exportCertification{{AcquiredAtLabel: v("acquired"), Name: v("cert")}},
		Portfolios:     []exportPortfolio{{Name: v("pname"), URL: v("url"), TechStack: ptr(v("ptech")), Overview: v("poverview")}},
		SnsPlatforms:   []exportSnsPlatform{{Name: v("sns"), URL: v("snsurl")}},
		SelfPromotions: []exportSelfPromotion{{Title: v("stitle"), Content: v("scontent")}},
	}
	b, err := renderMarkdown(m)
	if err != nil {
		t.Fatalf("Markdown を作れなかった: %v", err)
	}
	out := string(b)
	if strings.ContainsAny(out, `<>"'`) {
		t.Errorf("書き換えていない字が残った:\n%s", out)
	}
	// 値の数は、ひな形に出す文字列の欄が22、技術スタックの名前が4つの小分類で8である。
	if got := strings.Count(out, escaped); got != 30 {
		t.Errorf("書き換えた値の数が %d。期待は 30:\n%s", got, out)
	}
	for _, want := range []string{
		"**氏名：" + escaped + "name**",
		"- 開発言語：" + escaped + "1, " + escaped + "2\n",
		"技術スタック：" + escaped + "ptech\n",
		"- " + escaped + "sns: " + escaped + "snsurl\n",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("Markdown に %q が無い:\n%s", want, out)
		}
	}
}

// TestRenderMarkdown_Layout は、Markdown の空白と改行が、Java 版の Thymeleaf と同じ形になることを確かめる。
// 項目が最も少ない経歴書 601 は、正解のファイルと1バイトも違わないことを確かめる。項目が2つ以上の繰り返しは、
// 2回目からの繰り返しの先頭の改行を出さないことを確かめる。
func TestRenderMarkdown_Layout(t *testing.T) {
	t.Run("経歴書601", func(t *testing.T) {
		want, err := os.ReadFile("testdata/export/markdown/601.md")
		if err != nil {
			t.Fatal(err)
		}
		m := exportModel{
			Title: "職務経歴書", AsOfDateLabel: "2026年2月6日現在", FullName: "田中 次郎",
			Careers: []exportCareer{{PeriodLabel: "2020年4月 〜 現在", CompanyName: "株式会社すくない"}},
			CompanySections: []exportCompanySection{{
				CompanyLabel: "株式会社すくない", CompanyPeriodLabel: "2020年4月 〜 現在",
				Projects: []exportProject{{
					ProjectLabel: "社内の申請の画面の開発（2020年4月 〜 現在）",
					Overview:     "社内の申請を受け付ける画面を作った。", TeamComp: "全体3名", Role: "画面の実装を受け持った。",
					Achievements: []string{"申請の処理の時間を半分にした。"},
				}},
			}},
			SelfPromotions: []exportSelfPromotion{{Title: "A 手を抜かない", Content: "小さな作業でも、確かめてから終えます。"}},
		}
		got, err := renderMarkdown(m)
		if err != nil {
			t.Fatalf("Markdown を作れなかった: %v", err)
		}
		if string(got) != string(want) {
			t.Errorf("Markdown が正解のファイルと違う。Go 版:\n%q\nJava 版:\n%q", got, want)
		}
	})

	t.Run("2回目からの繰り返し", func(t *testing.T) {
		project := func(name string) exportProject {
			return exportProject{ProjectLabel: name, Achievements: []string{"a1", "a2"}}
		}
		m := exportModel{
			CompanySections: []exportCompanySection{
				{CompanyLabel: "C1", Projects: []exportProject{project("P1"), project("P2")}},
				{CompanyLabel: "C2", Projects: []exportProject{project("P3")}},
			},
			Portfolios: []exportPortfolio{
				{Name: "A", Overview: "o", URL: "u", TechStack: ptr("Go")},
				{Name: "B", Overview: "p", URL: "v", TechStack: ptr(" 　")},
				{Name: "C", Overview: "q", URL: "w"},
			},
			SelfPromotions: []exportSelfPromotion{{Title: "T1", Content: "x"}, {Title: "T2", Content: "y"}},
		}
		b, err := renderMarkdown(m)
		if err != nil {
			t.Fatalf("Markdown を作れなかった: %v", err)
		}
		// want は、同じ値を Java 版の Thymeleaf に入れて作った Markdown である。
		const want = "\n# \n\n****\n\n**氏名：**\n\n---\n\n## 職歴\n\n| 期間 | 会社名 |\n|------|--------|\n\n\n---\n\n## 職務内容\n\n\n### C1\n\n\n\n#### P1\n\n\n**プロジェクト概要：**\n\n\n\n**チーム構成：**\n\n\n\n**役割：**\n\n\n\n\n**主な成果：**\n\na1\na2\n\n\n\n\n**作業工程：**\n\n| 要件定義 | 基本設計 | 詳細設計 | 実装・単体テスト | 結合テスト | 総合テスト | 運用・保守 |\n|:--------:|:--------:|:--------:|:----------------:|:----------:|:----------:|:----------:|\n|  |  |  |  |  |  |  |\n\n\n\n#### P2\n\n\n**プロジェクト概要：**\n\n\n\n**チーム構成：**\n\n\n\n**役割：**\n\n\n\n\n**主な成果：**\n\na1\na2\n\n\n\n\n**作業工程：**\n\n| 要件定義 | 基本設計 | 詳細設計 | 実装・単体テスト | 結合テスト | 総合テスト | 運用・保守 |\n|:--------:|:--------:|:--------:|:----------------:|:----------:|:----------:|:----------:|\n|  |  |  |  |  |  |  |\n\n\n\n\n### C2\n\n\n\n#### P3\n\n\n**プロジェクト概要：**\n\n\n\n**チーム構成：**\n\n\n\n**役割：**\n\n\n\n\n**主な成果：**\n\na1\na2\n\n\n\n\n**作業工程：**\n\n| 要件定義 | 基本設計 | 詳細設計 | 実装・単体テスト | 結合テスト | 総合テスト | 運用・保守 |\n|:--------:|:--------:|:--------:|:----------------:|:----------:|:----------:|:----------:|\n|  |  |  |  |  |  |  |\n\n\n\n\n\n\n---\n\n\n\n\n## 個人開発・成果物\n\n\n**A**\no\nURL: u\n技術スタック：Go\n\n\n\n**B**\np\nURL: v\n\n\n\n**C**\nq\nURL: w\n\n\n\n\n\n---\n\n\n\n\n\n## 自己PR\n\n\n**T1**\nx\n\n\n**T2**\ny\n\n\n\n\n"
		if string(b) != want {
			t.Errorf("Markdown が Java 版と違う。Go 版:\n%q\nJava 版:\n%q", b, want)
		}
	})
}

// TestExecuteExportTemplate_Error は、ひな形に値を入れられないとき、誤りを返すことを確かめる。
func TestExecuteExportTemplate_Error(t *testing.T) {
	tmpl := template.Must(template.New("broken").Parse("{{.Missing}}"))
	b, err := executeExportTemplate(tmpl, exportModel{})
	var execErr template.ExecError
	if b != nil || !errors.As(err, &execErr) {
		t.Errorf("答え %q、誤り %v。期待は答えが無く、ひな形の誤りであること", b, err)
	}
}

// normalizeCSSSpace は、HTML の空白と改行の続きを1つの空白にする。CSS の規則を、字下げによらずに比べるためである。
func normalizeCSSSpace(s string) string {
	return strings.Join(strings.Fields(s), " ")
}

// cssRuleBody は、空白を1つにした HTML から、選び方が selector の CSS の規則の中身を返す。規則が無ければテストを止める。
func cssRuleBody(t *testing.T, html, selector string) string {
	t.Helper()
	start := strings.Index(html, "} "+selector+" { ")
	if start < 0 {
		t.Fatalf("CSS に %q の規則が無い:\n%s", selector, html)
	}
	body := html[start+len("} "+selector+" { "):]
	return body[:strings.Index(body, "}")]
}

// TestRenderPDFHTML_SettingsAndCSS は、利用者が選んだフォントと4つの文字の大きさと表の見出しの色が HTML の CSS に入ることと、
// Chromium で Java 版と同じ見た目にするための6つの CSS が HTML に入ることを確かめる。
func TestRenderPDFHTML_SettingsAndCSS(t *testing.T) {
	s := pdfSettings{
		FontFamily: "Noto Serif JP", TitleFontSize: 17.5, DateFontSize: 9, FullNameFontSize: 12.5,
		SectionHeadingFontSize: 72, TableHeaderColor: "#a1b2c3",
	}
	out, err := renderPDFHTML(exportModel{}, s)
	if err != nil {
		t.Fatalf("HTML を作れなかった: %v", err)
	}
	html := normalizeCSSSpace(out)

	t.Run("設定の値", func(t *testing.T) {
		for _, c := range []struct{ selector, decl string }{
			{"body", `font-family: "Noto Serif JP", sans-serif;`},
			{".document-title", "font-size: 17.5px;"},
			{".header-meta", "font-size: 9px;"},
			{".header-name-label", "font-size: 12.5px;"},
			{".section-title", "font-size: 72px;"},
			{".work-table th", "background-color: #a1b2c3;"},
			{".sub-table th", "background-color: #a1b2c3;"},
		} {
			if body := cssRuleBody(t, html, c.selector); !strings.Contains(body, c.decl) {
				t.Errorf("%s の規則に %q が無い: %q", c.selector, c.decl, body)
			}
		}
	})

	t.Run("既定のフォント", func(t *testing.T) {
		s := defaultPDFSettings()
		out, err := renderPDFHTML(exportModel{}, s)
		if err != nil {
			t.Fatalf("HTML を作れなかった: %v", err)
		}
		const want = `font-family: "Noto Sans JP", sans-serif;`
		if body := cssRuleBody(t, normalizeCSSSpace(out), "body"); !strings.Contains(body, want) {
			t.Errorf("body の規則に %q が無い: %q", want, body)
		}
	})

	t.Run("決まった2つのほかのフォント", func(t *testing.T) {
		s := s
		s.FontFamily = `Noto Sans JP"; } body { color: red`
		out, err := renderPDFHTML(exportModel{}, s)
		if out != "" || !errors.Is(err, errPDFFontFamilyUnknown) {
			t.Errorf("答え %q、誤り %v。期待は答えが無く、errPDFFontFamilyUnknown であること", out, err)
		}
	})

	t.Run("Java 版と同じ見た目にするための CSS", func(t *testing.T) {
		fontFace := func(family string, weight int, style, ps, ascent, descent string) string {
			return fmt.Sprintf(`@font-face { font-family: "%s"; font-weight: %d; src: local("%s %s"), local("%s"); `+
				`ascent-override: %s; descent-override: %s; }`, family, weight, family, style, ps, ascent, descent)
		}
		for _, want := range []string{
			// 2頁目から先の中身の位置を Java 版に合わせる。
			"@page { size: A4; margin: calc(9mm + 5.9pt) 11mm 9mm 11mm; } @page :first { margin-top: 9mm; }",
			// 改頁した先で、職務内容の表の見出しを繰り返さない。
			".work-table thead { display: table-row-group; }",
			// 職務内容の表の列の幅。
			".period-col { width: 87px; } .content-col { width: 400.33px; } .tech-col { width: auto; }",
			// 行の中で字を置く高さを Java 版に合わせる。
			fontFace("Noto Sans JP", 400, "Regular", "NotoSansJP-Regular", "112.1%", "32.7%"),
			fontFace("Noto Sans JP", 700, "Bold", "NotoSansJP-Bold", "112.1%", "32.7%"),
			fontFace("Noto Serif JP", 400, "Regular", "NotoSerifJP-Regular", "111.2%", "32.5%"),
			fontFace("Noto Serif JP", 700, "Bold", "NotoSerifJP-Bold", "111.2%", "32.5%"),
		} {
			if !strings.Contains(html, want) {
				t.Errorf("CSS に %q が無い:\n%s", want, html)
			}
		}
		for _, c := range []struct{ selector, decl string }{
			// SNS の項目の間を Java 版に合わせる。
			{".sns-item", "padding-top: 5.9pt;"},
			// 英字の合字を作らない。
			{"body", "font-variant-ligatures: none;"},
		} {
			if body := cssRuleBody(t, html, c.selector); !strings.Contains(body, c.decl) {
				t.Errorf("%s の規則に %q が無い: %q", c.selector, c.decl, body)
			}
		}
	})
}

// TestRenderPDFHTML_EscapesUserText は、PDF の HTML に出すすべての値で、利用者が書いた字を HTML として読まれない形で書き、
// 改行を書き換えずに残すことを確かめる。改行は、Java 版と同じく CSS の white-space: pre-line で出る。
func TestRenderPDFHTML_EscapesUserText(t *testing.T) {
	const raw = `<a&b>"c'`
	const escaped = `&lt;a&amp;b&gt;&#34;c&#39;`
	v := func(s string) string { return raw + s }
	m := exportModel{
		Title: v("title"), AsOfDateLabel: v("date"), FullName: v("name"),
		Careers: []exportCareer{{PeriodLabel: v("period"), CompanyName: v("company")}},
		CompanySections: []exportCompanySection{{
			CompanyLabel: v("label"), CompanyPeriodLabel: v("cperiod"),
			Projects: []exportProject{{
				PeriodStartLabel: v("start"), PeriodEndLabel: v("end"), ProjectLabel: v("project"), ProjectName: v("pname"),
				Overview: v("overview") + "\n2行目", TeamComp: v("team"), Role: v("role"),
				Achievements: []string{v("a1"), v("a2")},
				Process:      exportProcess{Label: v("process")},
				TechSections: []exportTechSection{{Title: v("ttitle"), Lines: []exportTechLine{{Label: v("tlabel"), Value: v("tvalue")}}}},
			}},
		}},
		Certifications: []exportCertification{{AcquiredAtLabel: v("acquired"), Name: v("cert")}},
		Portfolios:     []exportPortfolio{{Name: v("portfolio"), URL: v("url"), TechStack: ptr(v("ptech")), Overview: v("poverview")}},
		SnsPlatforms:   []exportSnsPlatform{{Name: v("sns"), URL: v("snsurl")}},
		SelfPromotions: []exportSelfPromotion{{Title: v("stitle"), Content: v("scontent") + "\n2行目"}},
	}
	out, err := renderPDFHTML(m, defaultPDFSettings())
	if err != nil {
		t.Fatalf("HTML を作れなかった: %v", err)
	}
	if strings.Contains(out, "<a&b>") {
		t.Errorf("書き換えていない字が残った:\n%s", out)
	}
	// 値の数は、出力のモデルの PDF に出す文字列の欄が29で、経歴書の名前を title と見出しの2か所に出すので30である。
	if got := strings.Count(out, escaped); got != 30 {
		t.Errorf("書き換えた値の数が %d。期待は 30:\n%s", got, out)
	}
	for _, want := range []string{
		"<title>" + escaped + "title</title>",
		`<p class="field-text">` + escaped + "overview\n2行目</p>",
		"<p>" + escaped + "scontent\n2行目</p>",
		"技術スタック：<span>" + escaped + "ptech</span>",
		"<span>" + escaped + "tlabel</span>：<span>" + escaped + "tvalue</span>",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("HTML に %q が無い:\n%s", want, out)
		}
	}
	html := normalizeCSSSpace(out)
	for _, selector := range []string{".field-text", ".portfolio-box p, .pr-section p"} {
		if body := cssRuleBody(t, html, selector); !strings.Contains(body, "white-space: pre-line;") {
			t.Errorf("%s の規則に white-space: pre-line が無い: %q", selector, body)
		}
	}
}
