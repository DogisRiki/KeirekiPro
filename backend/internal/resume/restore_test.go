package resume

import (
	"reflect"
	"strings"
	"testing"

	"github.com/google/uuid"
)

// restoreUser は、戻しのテストの、要求を送った利用者である。
var restoreUser = uuid.MustParse("00000000-0000-4000-8000-000000000001")

// validRestore は、Java 版が戻しで確かめる値の決まりをすべて満たす、6つの欄に1件ずつ項目を持つ戻しの経歴書を返す。
func validRestore() *rsResume {
	return &rsResume{
		name: ptr("戻す経歴書"), date: &Date{2026, 1, 2}, lastName: ptr("山田"), firstName: ptr("太郎"),
		careers: []*rsCareer{{
			companyName: ptr("株式会社一"), startDate: &YearMonth{2010, 4}, endDate: &YearMonth{2015, 3},
		}},
		projects: []*rsProject{{
			companyName: ptr("株式会社一"), startDate: &YearMonth{2011, 4}, active: true,
			name: ptr("案件"), overview: ptr("概要"), teamComp: ptr("5名"), role: ptr("開発"), achievement: ptr("成果"),
			process:   Process{Requirements: true, Maintenance: true},
			techStack: TechStack{Backend: BackendStacks[*string]{Languages: []*string{ptr("Go")}}},
		}},
		certifications: []*rsCertification{{name: ptr("基本情報技術者"), date: &YearMonth{2012, 5}}},
		portfolios: []*rsPortfolio{{
			name: ptr("作品"), overview: ptr("説明"), techStack: ptr("Go"), link: ptr("https://example.com"),
		}},
		snsPlatforms:   []*rsSnsPlatform{{name: ptr("GitHub"), link: ptr("https://github.com/x")}},
		selfPromotions: []*rsSelfPromotion{{title: ptr("題"), content: ptr("中身")}},
	}
}

// restoredIDs は、経歴書 r と6つの欄の項目の ID を集める。
func restoredIDs(r Resume) []uuid.UUID {
	ids := []uuid.UUID{r.ID}
	for _, e := range r.Careers {
		ids = append(ids, e.ID)
	}
	for _, e := range r.Projects {
		ids = append(ids, e.ID)
	}
	for _, e := range r.Certifications {
		ids = append(ids, e.ID)
	}
	for _, e := range r.Portfolios {
		ids = append(ids, e.ID)
	}
	for _, e := range r.SnsPlatforms {
		ids = append(ids, e.ID)
	}
	for _, e := range r.SelfPromotions {
		ids = append(ids, e.ID)
	}
	return ids
}

// withoutIDs は、経歴書 r と6つの欄の項目の ID を uuid.Nil にした経歴書を返す。ID は戻すたびに新しく決まるので、比べる前に消す。
func withoutIDs(r Resume) Resume {
	r.ID = uuid.Nil
	for i := range r.Careers {
		r.Careers[i].ID = uuid.Nil
	}
	for i := range r.Projects {
		r.Projects[i].ID = uuid.Nil
	}
	for i := range r.Certifications {
		r.Certifications[i].ID = uuid.Nil
	}
	for i := range r.Portfolios {
		r.Portfolios[i].ID = uuid.Nil
	}
	for i := range r.SnsPlatforms {
		r.SnsPlatforms[i].ID = uuid.Nil
	}
	for i := range r.SelfPromotions {
		r.SelfPromotions[i].ID = uuid.Nil
	}
	return r
}

// TestBuildRestored_Rules は、buildRestored が、Service の戻しの節の値の決まりのそれぞれで、決まりを満たす値と満たさない値を
// 分けることを確かめる(要件4の受入基準5)。長さは Java の String.length と同じく UTF-16 の単位で数える。
func TestBuildRestored_Rules(t *testing.T) {
	t.Run("決まりを満たす経歴書は、利用者と新しい ID を付けて値をそのまま写す", func(t *testing.T) {
		got, ok := buildRestored(validRestore(), restoreUser)
		if !ok {
			t.Fatal("決まりを満たす経歴書を断った")
		}
		seen := map[uuid.UUID]bool{}
		for _, id := range restoredIDs(got) {
			if id == uuid.Nil || seen[id] {
				t.Errorf("ID が無いか重なっている: %v", restoredIDs(got))
			}
			seen[id] = true
		}
		want := Resume{
			UserID: restoreUser, Name: "戻す経歴書", Date: Date{2026, 1, 2}, LastName: ptr("山田"), FirstName: ptr("太郎"),
			Careers: []Career{{CompanyName: "株式会社一", Period: Period{StartDate: YearMonth{2010, 4}, EndDate: &YearMonth{2015, 3}}}},
			Projects: []Project{{
				CompanyName: "株式会社一", Period: Period{StartDate: YearMonth{2011, 4}, Active: true},
				Name: "案件", Overview: "概要", TeamComp: "5名", Role: "開発", Achievement: "成果",
				Process:   Process{Requirements: true, Maintenance: true},
				TechStack: TechStack{Backend: BackendStacks[*string]{Languages: []*string{ptr("Go")}}},
			}},
			Certifications: []Certification{{Name: "基本情報技術者", Date: YearMonth{2012, 5}}},
			Portfolios:     []Portfolio{{Name: "作品", Overview: "説明", TechStack: ptr("Go"), Link: "https://example.com"}},
			SnsPlatforms:   []SnsPlatform{{Name: "GitHub", Link: "https://github.com/x"}},
			SelfPromotions: []SelfPromotion{{Title: "題", Content: "中身"}},
		}
		if g := withoutIDs(got); !reflect.DeepEqual(g, want) {
			t.Errorf("戻した経歴書:\n got %+v\nwant %+v", g, want)
		}
	})

	// lone は、対になっていないサロゲート U+D800 の WTF-8 のバイトである。Java の String.length は1と数える。
	const lone = "\xed\xa0\x80"
	emoji := strings.Repeat("\U0001F600", 25)
	cases := []struct {
		name   string
		mutate func(r *rsResume)
		ok     bool
	}{
		// 経歴書の名前(ResumeName)
		{"名前の無い経歴書", func(r *rsResume) { r.name = nil }, false},
		{"空白だけの名前", func(r *rsResume) { r.name = ptr(" \t　") }, false},
		{"50文字の名前", func(r *rsResume) { r.name = ptr(strings.Repeat("あ", 50)) }, true},
		{"50文字を超える名前", func(r *rsResume) { r.name = ptr(strings.Repeat("あ", 51)) }, false},
		{"BMP の外の字25字の名前は50文字", func(r *rsResume) { r.name = ptr(emoji) }, true},
		{"BMP の外の字25字と1字の名前は51文字", func(r *rsResume) { r.name = ptr(emoji + "あ") }, false},
		{"対になっていないサロゲートは1文字", func(r *rsResume) { r.name = ptr(lone + strings.Repeat("あ", 49)) }, true},
		{"使えない字を含む名前", func(r *rsResume) { r.name = ptr("経歴書/一") }, false},
		{"使えない字と行の区切りの字を含む名前", func(r *rsResume) { r.name = ptr("経歴書/一\u2028") }, true},
		{". で始まる名前", func(r *rsResume) { r.name = ptr(".経歴書") }, false},
		{". で終わる名前", func(r *rsResume) { r.name = ptr("経歴書.") }, false},
		// 日付
		{"日付の無い経歴書", func(r *rsResume) { r.date = nil }, false},
		// 氏名(FullName)
		{"姓だけの経歴書", func(r *rsResume) { r.firstName = nil }, false},
		{"名だけの経歴書", func(r *rsResume) { r.lastName = nil }, false},
		{"名が空白だけの経歴書", func(r *rsResume) { r.firstName = ptr("  ") }, false},
		{"10文字の姓", func(r *rsResume) { r.lastName = ptr(strings.Repeat("山", 10)) }, true},
		{"10文字を超える姓", func(r *rsResume) { r.lastName = ptr(strings.Repeat("山", 11)) }, false},
		{"10文字を超える名", func(r *rsResume) { r.firstName = ptr(strings.Repeat("a", 11)) }, false},
		{"使えない字を含む姓", func(r *rsResume) { r.lastName = ptr("山田1") }, false},
		{"使えない字を含む名", func(r *rsResume) { r.firstName = ptr("太郎" + lone) }, false},
		// 職歴(CompanyName と Period)
		{"会社の名前の無い職歴", func(r *rsResume) { r.careers[0].companyName = nil }, false},
		{"会社の名前が空白だけの職歴", func(r *rsResume) { r.careers[0].companyName = ptr(" ") }, false},
		{"会社の名前が50文字を超える職歴", func(r *rsResume) { r.careers[0].companyName = ptr(strings.Repeat("社", 51)) }, false},
		{"始まりの年月の無い職歴", func(r *rsResume) { r.careers[0].startDate = nil }, false},
		{"続いていないのに終わりの年月の無い職歴", func(r *rsResume) { r.careers[0].endDate = nil }, false},
		{"始まりの年月より前の終わりの年月", func(r *rsResume) { r.careers[0].endDate = &YearMonth{2010, 3} }, false},
		{"始まりの年月と同じ終わりの年月", func(r *rsResume) { r.careers[0].endDate = &YearMonth{2010, 4} }, true},
		{"続いているのに終わりの年月がある職歴", func(r *rsResume) { r.careers[0].active = true }, false},
		{"続いていて終わりの年月の無い職歴", func(r *rsResume) { r.careers[0].active, r.careers[0].endDate = true, nil }, true},
		// プロジェクト(Project と CompanyName と Period)
		{"会社の名前の無いプロジェクト", func(r *rsResume) { r.projects[0].companyName = nil }, false},
		{"始まりの年月の無いプロジェクト", func(r *rsResume) { r.projects[0].startDate = nil }, false},
		{"続いているのに終わりの年月があるプロジェクト", func(r *rsResume) { r.projects[0].endDate = &YearMonth{2012, 1} }, false},
		{"始まりの年月より前の終わりの年月のプロジェクト", func(r *rsResume) {
			r.projects[0].active, r.projects[0].endDate = false, &YearMonth{2011, 3}
		}, false},
		{"名前の無いプロジェクト", func(r *rsResume) { r.projects[0].name = nil }, false},
		{"名前が50文字を超えるプロジェクト", func(r *rsResume) { r.projects[0].name = ptr(strings.Repeat("案", 51)) }, false},
		{"概要が空白だけのプロジェクト", func(r *rsResume) { r.projects[0].overview = ptr("\n") }, false},
		{"概要が1000文字のプロジェクト", func(r *rsResume) { r.projects[0].overview = ptr(strings.Repeat("概", 1000)) }, true},
		{"概要が1000文字を超えるプロジェクト", func(r *rsResume) { r.projects[0].overview = ptr(strings.Repeat("概", 1001)) }, false},
		{"体制が100文字を超えるプロジェクト", func(r *rsResume) { r.projects[0].teamComp = ptr(strings.Repeat("名", 101)) }, false},
		{"体制の無いプロジェクト", func(r *rsResume) { r.projects[0].teamComp = nil }, false},
		{"役割の無いプロジェクト", func(r *rsResume) { r.projects[0].role = nil }, false},
		{"役割が1000文字を超えるプロジェクト", func(r *rsResume) { r.projects[0].role = ptr(strings.Repeat("役", 1001)) }, false},
		{"成果が空白だけのプロジェクト", func(r *rsResume) { r.projects[0].achievement = ptr(" ") }, false},
		{"成果が1000文字を超えるプロジェクト", func(r *rsResume) { r.projects[0].achievement = ptr(strings.Repeat("成", 1001)) }, false},
		// 資格(Certification)
		{"名前の無い資格", func(r *rsResume) { r.certifications[0].name = nil }, false},
		{"名前が50文字を超える資格", func(r *rsResume) { r.certifications[0].name = ptr(strings.Repeat("資", 51)) }, false},
		{"年月の無い資格", func(r *rsResume) { r.certifications[0].date = nil }, false},
		// ポートフォリオ(Portfolio と Link)
		{"名前の無いポートフォリオ", func(r *rsResume) { r.portfolios[0].name = nil }, false},
		{"名前が50文字を超えるポートフォリオ", func(r *rsResume) { r.portfolios[0].name = ptr(strings.Repeat("作", 51)) }, false},
		{"概要の無いポートフォリオ", func(r *rsResume) { r.portfolios[0].overview = nil }, false},
		{"概要が1000文字を超えるポートフォリオ", func(r *rsResume) { r.portfolios[0].overview = ptr(strings.Repeat("説", 1001)) }, false},
		{"技術の無いポートフォリオ", func(r *rsResume) { r.portfolios[0].techStack = nil }, true},
		{"技術が空のポートフォリオ", func(r *rsResume) { r.portfolios[0].techStack = ptr("") }, true},
		{"技術が1000文字を超えるポートフォリオ", func(r *rsResume) { r.portfolios[0].techStack = ptr(strings.Repeat("技", 1001)) }, false},
		{"リンクの無いポートフォリオ", func(r *rsResume) { r.portfolios[0].link = nil }, false},
		{"リンクが空白だけのポートフォリオ", func(r *rsResume) { r.portfolios[0].link = ptr("  ") }, false},
		{"https でないリンク", func(r *rsResume) { r.portfolios[0].link = ptr("http://example.com") }, false},
		{"スキームの無いリンク", func(r *rsResume) { r.portfolios[0].link = ptr("example.com/a") }, false},
		{"URI として読めないリンク", func(r *rsResume) { r.portfolios[0].link = ptr("https://example.com/a b") }, false},
		{"大文字の HTTPS のリンク", func(r *rsResume) { r.portfolios[0].link = ptr("HTTPS://example.com") }, true},
		{"ホストの無い https のリンク", func(r *rsResume) { r.portfolios[0].link = ptr("https:x") }, true},
		// SNS(SnsPlatform と Link)
		{"名前の無い SNS", func(r *rsResume) { r.snsPlatforms[0].name = nil }, false},
		{"名前が50文字を超える SNS", func(r *rsResume) { r.snsPlatforms[0].name = ptr(strings.Repeat("s", 51)) }, false},
		{"https でないリンクの SNS", func(r *rsResume) { r.snsPlatforms[0].link = ptr("ftp://example.com") }, false},
		{"リンクの無い SNS", func(r *rsResume) { r.snsPlatforms[0].link = nil }, false},
		// 自己PR(SelfPromotion)
		{"題の無い自己PR", func(r *rsResume) { r.selfPromotions[0].title = nil }, false},
		{"題が50文字を超える自己PR", func(r *rsResume) { r.selfPromotions[0].title = ptr(strings.Repeat("題", 51)) }, false},
		{"中身が空白だけの自己PR", func(r *rsResume) { r.selfPromotions[0].content = ptr(" ") }, false},
		{"中身が1000文字を超える自己PR", func(r *rsResume) { r.selfPromotions[0].content = ptr(strings.Repeat("中", 1001)) }, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r := validRestore()
			c.mutate(r)
			if _, ok := buildRestored(r, restoreUser); ok != c.ok {
				t.Errorf("buildRestored の ok = %v。want %v", ok, c.ok)
			}
		})
	}
}

// TestBuildRestored_LaxRules は、利用者が画面で保存するときの決まりのうち、Java 版の戻しが確かめない6つの決まりに当たる値を、
// buildRestored が断らないことを確かめる(要件4の受入基準5)。
func TestBuildRestored_LaxRules(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(r *rsResume)
	}{
		{"1900年から2100年の外の年月と日付", func(r *rsResume) {
			r.date = &Date{1800, 1, 1}
			r.careers[0].startDate, r.careers[0].endDate = &YearMonth{1899, 12}, &YearMonth{2101, 1}
			r.certifications[0].date = &YearMonth{2200, 1}
		}},
		{"期間が重なる職歴", func(r *rsResume) {
			r.careers = append(r.careers, &rsCareer{
				companyName: ptr("株式会社二"), startDate: &YearMonth{2012, 1}, endDate: &YearMonth{2018, 1},
			})
		}},
		{"255文字を超えるリンク", func(r *rsResume) {
			r.portfolios[0].link = ptr("https://example.com/" + strings.Repeat("a", 300))
			r.snsPlatforms[0].link = ptr("https://example.com/" + strings.Repeat("b", 300))
		}},
		{"姓と名の両方が無い経歴書", func(r *rsResume) { r.lastName, r.firstName = nil, nil }},
		{"工程を1つも選んでいないプロジェクト", func(r *rsResume) { r.projects[0].process = Process{} }},
		{"欄ごとの項目の数の上限を超える経歴書", func(r *rsResume) {
			r.careers = repeatEntry(r.careers[0], careerLimit.limit+1)
			r.projects = repeatEntry(r.projects[0], projectLimit.limit+1)
			r.certifications = repeatEntry(r.certifications[0], certificationLimit.limit+1)
			r.portfolios = repeatEntry(r.portfolios[0], portfolioLimit.limit+1)
			r.snsPlatforms = repeatEntry(r.snsPlatforms[0], snsPlatformLimit.limit+1)
			r.selfPromotions = repeatEntry(r.selfPromotions[0], selfPromotionLimit.limit+1)
		}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r := validRestore()
			c.mutate(r)
			if _, ok := buildRestored(r, restoreUser); !ok {
				t.Error("Java 版の戻しが確かめない決まりに当たる値を断った")
			}
		})
	}
}

// repeatEntry は、項目 e を n 個並べた並びを返す。
func repeatEntry[E any](e *E, n int) []*E {
	out := make([]*E, n)
	for i := range out {
		c := *e
		out[i] = &c
	}
	return out
}

// TestBuildRestored_Defaults は、ファイルの中に無い欄と値を、buildRestored が Java 版と同じに補うことを確かめる(要件2の受入基準2)。
// 本文は readRestoreFile で読み、読んだ経歴書を buildRestored に渡す。
func TestBuildRestored_Defaults(t *testing.T) {
	restore := func(t *testing.T, resume string) Resume {
		t.Helper()
		f, ok := readRestoreFile([]byte(`{"version":"1.0","resume":` + resume + `}`))
		if !ok || f.resume == nil {
			t.Fatalf("本文を読めない: %s", resume)
		}
		got, ok := buildRestored(f.resume, restoreUser)
		if !ok {
			t.Fatalf("buildRestored が断った: %s", resume)
		}
		return got
	}

	t.Run("無い欄は項目の無い欄にし、姓と名の無い経歴書は氏名の無い経歴書にする", func(t *testing.T) {
		got := restore(t, `{"resumeName":"経歴書","date":"2026-01-02"}`)
		want := Resume{
			UserID: restoreUser, Name: "経歴書", Date: Date{2026, 1, 2},
			Careers: []Career{}, Projects: []Project{}, Certifications: []Certification{},
			Portfolios: []Portfolio{}, SnsPlatforms: []SnsPlatform{}, SelfPromotions: []SelfPromotion{},
		}
		if g := withoutIDs(got); !reflect.DeepEqual(g, want) {
			t.Errorf("戻した経歴書:\n got %#v\nwant %#v", g, want)
		}
	})

	t.Run("null の欄は項目の無い欄にする", func(t *testing.T) {
		got := restore(t, `{"resumeName":"経歴書","date":"2026-01-02","careers":null,"projects":null,`+
			`"certifications":null,"portfolios":null,"snsPlatforms":null,"selfPromotions":null}`)
		if got.Careers == nil || got.Projects == nil || got.Certifications == nil ||
			got.Portfolios == nil || got.SnsPlatforms == nil || got.SelfPromotions == nil ||
			len(got.Careers)+len(got.Projects)+len(got.Certifications)+len(got.Portfolios)+
				len(got.SnsPlatforms)+len(got.SelfPromotions) != 0 {
			t.Errorf("項目の無い欄にならない: %#v", got)
		}
	})

	for _, names := range []string{
		`"lastName":"","firstName":""`,
		`"lastName":" ","firstName":"　"`,
		`"lastName":null`,
		`"firstName":"\t"`,
	} {
		t.Run("姓と名の両方が空か空白だけなら氏名の無い経歴書にする "+names, func(t *testing.T) {
			got := restore(t, `{"resumeName":"経歴書","date":"2026-01-02",`+names+`}`)
			if got.LastName != nil || got.FirstName != nil {
				t.Errorf("姓 = %v、名 = %v。want 両方とも無い", got.LastName, got.FirstName)
			}
		})
	}

	t.Run("工程と技術の無いプロジェクトは、工程と技術を選んでいないものにする", func(t *testing.T) {
		got := restore(t, `{"resumeName":"経歴書","date":"2026-01-02","projects":[{"companyName":"会社",`+
			`"startDate":"2020-01","active":true,"name":"案件","overview":"概要","teamComp":"3名","role":"開発","achievement":"成果"}]}`)
		if len(got.Projects) != 1 {
			t.Fatalf("プロジェクトの数 = %d。want 1", len(got.Projects))
		}
		if p := got.Projects[0]; p.Process != (Process{}) || !reflect.DeepEqual(p.TechStack, emptyTechStack()) {
			t.Errorf("工程 = %+v、技術 = %+v。want 選んでいないもの", p.Process, p.TechStack)
		}
	})
}

// TestBuildRestored_SortsEntries は、buildRestored が、6つの欄の項目を、経歴書を読み出すときと同じ sortEntries の順に並べることを
// 確かめる(要件2の受入基準1)。
func TestBuildRestored_SortsEntries(t *testing.T) {
	r := validRestore()
	career := func(name string, start YearMonth, end *YearMonth) *rsCareer {
		return &rsCareer{companyName: ptr(name), startDate: &start, endDate: end, active: end == nil}
	}
	r.careers = []*rsCareer{
		career("古い会社", YearMonth{2010, 4}, &YearMonth{2012, 3}),
		career("今の会社", YearMonth{2015, 4}, nil),
		career("中の会社", YearMonth{2013, 4}, &YearMonth{2014, 3}),
	}
	project := func(name string, start YearMonth) *rsProject {
		p := *r.projects[0]
		p.name, p.startDate = ptr(name), &start
		return &p
	}
	r.projects = []*rsProject{project("中の案件", YearMonth{2016, 1}), project("古い案件", YearMonth{2014, 1}), project("新しい案件", YearMonth{2020, 1})}
	r.certifications = []*rsCertification{
		{name: ptr("古い資格"), date: &YearMonth{2010, 1}},
		{name: ptr("新しい資格"), date: &YearMonth{2020, 1}},
		{name: ptr("中の資格"), date: &YearMonth{2015, 1}},
	}
	portfolio := func(name string) *rsPortfolio {
		return &rsPortfolio{name: ptr(name), overview: ptr("説明"), link: ptr("https://example.com")}
	}
	r.portfolios = []*rsPortfolio{portfolio("う作品"), portfolio("あ作品"), portfolio("い作品")}
	r.snsPlatforms = []*rsSnsPlatform{
		{name: ptr("Zenn"), link: ptr("https://zenn.dev")},
		{name: ptr("GitHub"), link: ptr("https://github.com")},
		{name: ptr("Qiita"), link: ptr("https://qiita.com")},
	}
	r.selfPromotions = []*rsSelfPromotion{{title: ptr("C 題"), content: ptr("中身")}, {title: ptr("A 題"), content: ptr("中身")}, {title: ptr("B 題"), content: ptr("中身")}}

	got, ok := buildRestored(r, restoreUser)
	if !ok {
		t.Fatal("決まりを満たす経歴書を断った")
	}
	var view backupOrderView
	for _, e := range got.Careers {
		view.Careers = append(view.Careers, e.CompanyName)
	}
	for _, e := range got.Projects {
		view.Projects = append(view.Projects, e.Name)
	}
	for _, e := range got.Certifications {
		view.Certifications = append(view.Certifications, e.Name)
	}
	for _, e := range got.Portfolios {
		view.Portfolios = append(view.Portfolios, e.Name)
	}
	for _, e := range got.SnsPlatforms {
		view.SnsPlatforms = append(view.SnsPlatforms, e.Name)
	}
	for _, e := range got.SelfPromotions {
		view.SelfPromotions = append(view.SelfPromotions, e.Title)
	}
	want := backupOrderView{
		Careers:        []string{"今の会社", "中の会社", "古い会社"},
		Projects:       []string{"新しい案件", "中の案件", "古い案件"},
		Certifications: []string{"新しい資格", "中の資格", "古い資格"},
		Portfolios:     []string{"あ作品", "い作品", "う作品"},
		SnsPlatforms:   []string{"GitHub", "Qiita", "Zenn"},
		SelfPromotions: []string{"A 題", "B 題", "C 題"},
	}
	if !reflect.DeepEqual(view, want) {
		t.Errorf("項目の順:\n got %+v\nwant %+v", view, want)
	}
}
