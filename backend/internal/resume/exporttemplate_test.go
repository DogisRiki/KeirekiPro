package resume

import (
	"errors"
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
