package resume

import (
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

// restoreUser は、戻しのテストの、要求を送った利用者である。
var restoreUser = uuid.MustParse("00000000-0000-4000-8000-000000000001")

// validRestore は、戻しで確かめる値の決まりをすべて満たす、6つの欄に1件ずつ項目を持つ戻しの経歴書を返す。
func validRestore() *rsResume {
	return &rsResume{
		Name: ptr("戻す経歴書"), Date: dt(2026, 1, 2), LastName: ptr("山田"), FirstName: ptr("太郎"),
		Careers: []*rsCareer{{
			CompanyName: ptr("株式会社一"), StartDate: ym(2010, 4), EndDate: ym(2015, 3),
		}},
		Projects: []*rsProject{{
			CompanyName: ptr("株式会社一"), StartDate: ym(2011, 4), Active: true,
			Name: ptr("案件"), Overview: ptr("概要"), TeamComp: ptr("5名"), Role: ptr("開発"), Achievement: ptr("成果"),
			Process:   bkProcess{Requirements: true, Maintenance: true},
			TechStack: TechStack{Backend: BackendStacks[*string]{Languages: []*string{ptr("Go")}}},
		}},
		Certifications: []*rsCertification{{Name: ptr("基本情報技術者"), Date: ym(2012, 5)}},
		Portfolios: []*rsPortfolio{{
			Name: ptr("作品"), Overview: ptr("説明"), TechStack: ptr("Go"), Link: ptr("https://example.com"),
		}},
		SnsPlatforms:   []*rsSnsPlatform{{Name: ptr("GitHub"), Link: ptr("https://github.com/x")}},
		SelfPromotions: []*rsSelfPromotion{{Title: ptr("題"), Content: ptr("中身")}},
	}
}

// ym は、値のある年月の欄を返す。
func ym(year, month int) jsonYearMonth {
	return jsonYearMonth{Value: YearMonth{year, time.Month(month)}, Present: true}
}

// dt は、値のある日付の欄を返す。
func dt(year, month, day int) jsonDate {
	return jsonDate{Value: Date{year, time.Month(month), day}, Present: true}
}

// emptyStacks は、35の小分類をすべて空の並びにした技術スタックを返す。
func emptyStacks() TechStack {
	var t TechStack
	fillEmptyStacks(&t)
	return t
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
// 分けることを確かめる(要件4の受入基準5)。長さは UTF-16 の単位で数える。
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

	checkDiffTableInChangedBehaviors(t, map[string]string{"使えない字を含む名前と空白だけの値の戻し": "CB-116"})
	emoji := strings.Repeat("\U0001F600", 25)
	cases := []struct {
		name   string
		mutate func(r *rsResume)
		ok     bool
	}{
		// 経歴書の名前(ResumeName)
		{"名前の無い経歴書", func(r *rsResume) { r.Name = nil }, false},
		{"空白だけの名前", func(r *rsResume) { r.Name = ptr(" \t　") }, false},
		{"50文字の名前", func(r *rsResume) { r.Name = ptr(strings.Repeat("あ", 50)) }, true},
		{"50文字を超える名前", func(r *rsResume) { r.Name = ptr(strings.Repeat("あ", 51)) }, false},
		{"BMP の外の字25字の名前は50文字", func(r *rsResume) { r.Name = ptr(emoji) }, true},
		{"BMP の外の字25字と1字の名前は51文字", func(r *rsResume) { r.Name = ptr(emoji + "あ") }, false},
		{"置き換えの字 U+FFFD は1文字", func(r *rsResume) { r.Name = ptr("�" + strings.Repeat("あ", 49)) }, true},
		// 使えない字は確かめない(変えた動きの一覧の CB-116)。
		{"使えない字を含む名前", func(r *rsResume) { r.Name = ptr("経歴書/一") }, true},
		{"使えない字と行の区切りの字を含む名前", func(r *rsResume) { r.Name = ptr("経歴書/一\u2028") }, true},
		// 空白だけかは unicode.IsSpace で決める(変えた動きの一覧の CB-116)。
		{"改行しない空白だけの名前", func(r *rsResume) { r.Name = ptr("\u00a0") }, false},
		{"情報の区切りの制御の字だけの名前", func(r *rsResume) { r.Name = ptr("\u001c") }, true},
		{". で始まる名前", func(r *rsResume) { r.Name = ptr(".経歴書") }, false},
		{". で終わる名前", func(r *rsResume) { r.Name = ptr("経歴書.") }, false},
		// 日付
		{"日付の無い経歴書", func(r *rsResume) { r.Date = jsonDate{} }, false},
		// 氏名(FullName)
		{"姓だけの経歴書", func(r *rsResume) { r.FirstName = nil }, false},
		{"名だけの経歴書", func(r *rsResume) { r.LastName = nil }, false},
		{"名が空白だけの経歴書", func(r *rsResume) { r.FirstName = ptr("  ") }, false},
		{"10文字の姓", func(r *rsResume) { r.LastName = ptr(strings.Repeat("山", 10)) }, true},
		{"10文字を超える姓", func(r *rsResume) { r.LastName = ptr(strings.Repeat("山", 11)) }, false},
		{"10文字を超える名", func(r *rsResume) { r.FirstName = ptr(strings.Repeat("a", 11)) }, false},
		{"使えない字を含む姓", func(r *rsResume) { r.LastName = ptr("山田1") }, false},
		{"使えない字を含む名", func(r *rsResume) { r.FirstName = ptr("太郎�") }, false},
		// 職歴(CompanyName と Period)
		{"会社の名前の無い職歴", func(r *rsResume) { r.Careers[0].CompanyName = nil }, false},
		{"会社の名前が空白だけの職歴", func(r *rsResume) { r.Careers[0].CompanyName = ptr(" ") }, false},
		{"会社の名前が50文字を超える職歴", func(r *rsResume) { r.Careers[0].CompanyName = ptr(strings.Repeat("社", 51)) }, false},
		{"始まりの年月の無い職歴", func(r *rsResume) { r.Careers[0].StartDate = jsonYearMonth{} }, false},
		{"続いていないのに終わりの年月の無い職歴", func(r *rsResume) { r.Careers[0].EndDate = jsonYearMonth{} }, false},
		{"始まりの年月より前の終わりの年月", func(r *rsResume) { r.Careers[0].EndDate = ym(2010, 3) }, false},
		{"始まりの年月と同じ終わりの年月", func(r *rsResume) { r.Careers[0].EndDate = ym(2010, 4) }, true},
		{"続いているのに終わりの年月がある職歴", func(r *rsResume) { r.Careers[0].Active = true }, false},
		{"続いていて終わりの年月の無い職歴", func(r *rsResume) { r.Careers[0].Active, r.Careers[0].EndDate = true, jsonYearMonth{} }, true},
		// プロジェクト(Project と CompanyName と Period)
		{"会社の名前の無いプロジェクト", func(r *rsResume) { r.Projects[0].CompanyName = nil }, false},
		{"始まりの年月の無いプロジェクト", func(r *rsResume) { r.Projects[0].StartDate = jsonYearMonth{} }, false},
		{"続いているのに終わりの年月があるプロジェクト", func(r *rsResume) { r.Projects[0].EndDate = ym(2012, 1) }, false},
		{"始まりの年月より前の終わりの年月のプロジェクト", func(r *rsResume) {
			r.Projects[0].Active, r.Projects[0].EndDate = false, ym(2011, 3)
		}, false},
		{"名前の無いプロジェクト", func(r *rsResume) { r.Projects[0].Name = nil }, false},
		{"名前が50文字を超えるプロジェクト", func(r *rsResume) { r.Projects[0].Name = ptr(strings.Repeat("案", 51)) }, false},
		{"概要が空白だけのプロジェクト", func(r *rsResume) { r.Projects[0].Overview = ptr("\n") }, false},
		{"概要が1000文字のプロジェクト", func(r *rsResume) { r.Projects[0].Overview = ptr(strings.Repeat("概", 1000)) }, true},
		{"概要が1000文字を超えるプロジェクト", func(r *rsResume) { r.Projects[0].Overview = ptr(strings.Repeat("概", 1001)) }, false},
		{"体制が100文字を超えるプロジェクト", func(r *rsResume) { r.Projects[0].TeamComp = ptr(strings.Repeat("名", 101)) }, false},
		{"体制の無いプロジェクト", func(r *rsResume) { r.Projects[0].TeamComp = nil }, false},
		{"役割の無いプロジェクト", func(r *rsResume) { r.Projects[0].Role = nil }, false},
		{"役割が1000文字を超えるプロジェクト", func(r *rsResume) { r.Projects[0].Role = ptr(strings.Repeat("役", 1001)) }, false},
		{"成果が空白だけのプロジェクト", func(r *rsResume) { r.Projects[0].Achievement = ptr(" ") }, false},
		{"成果が1000文字を超えるプロジェクト", func(r *rsResume) { r.Projects[0].Achievement = ptr(strings.Repeat("成", 1001)) }, false},
		// 資格(Certification)
		{"名前の無い資格", func(r *rsResume) { r.Certifications[0].Name = nil }, false},
		{"名前が50文字を超える資格", func(r *rsResume) { r.Certifications[0].Name = ptr(strings.Repeat("資", 51)) }, false},
		{"年月の無い資格", func(r *rsResume) { r.Certifications[0].Date = jsonYearMonth{} }, false},
		// ポートフォリオ(Portfolio と Link)
		{"名前の無いポートフォリオ", func(r *rsResume) { r.Portfolios[0].Name = nil }, false},
		{"名前が50文字を超えるポートフォリオ", func(r *rsResume) { r.Portfolios[0].Name = ptr(strings.Repeat("作", 51)) }, false},
		{"概要の無いポートフォリオ", func(r *rsResume) { r.Portfolios[0].Overview = nil }, false},
		{"概要が1000文字を超えるポートフォリオ", func(r *rsResume) { r.Portfolios[0].Overview = ptr(strings.Repeat("説", 1001)) }, false},
		{"技術の無いポートフォリオ", func(r *rsResume) { r.Portfolios[0].TechStack = nil }, true},
		{"技術が空のポートフォリオ", func(r *rsResume) { r.Portfolios[0].TechStack = ptr("") }, true},
		{"技術が1000文字を超えるポートフォリオ", func(r *rsResume) { r.Portfolios[0].TechStack = ptr(strings.Repeat("技", 1001)) }, false},
		{"リンクの無いポートフォリオ", func(r *rsResume) { r.Portfolios[0].Link = nil }, false},
		{"リンクが空白だけのポートフォリオ", func(r *rsResume) { r.Portfolios[0].Link = ptr("  ") }, false},
		{"https でないリンク", func(r *rsResume) { r.Portfolios[0].Link = ptr("http://example.com") }, false},
		{"スキームの無いリンク", func(r *rsResume) { r.Portfolios[0].Link = ptr("example.com/a") }, false},
		// Java 版は URI として読めないリンクを断った。Go 版は https: で始まれば戻す(CB-110)
		{"URI として読めないリンク", func(r *rsResume) { r.Portfolios[0].Link = ptr("https://example.com/a b") }, true},
		{"url: を前に付けたリンク", func(r *rsResume) { r.Portfolios[0].Link = ptr("url:https://example.com") }, true},
		{"大文字の HTTPS のリンク", func(r *rsResume) { r.Portfolios[0].Link = ptr("HTTPS://example.com") }, true},
		{"ホストの無い https のリンク", func(r *rsResume) { r.Portfolios[0].Link = ptr("https:x") }, true},
		// SNS(SnsPlatform と Link)
		{"名前の無い SNS", func(r *rsResume) { r.SnsPlatforms[0].Name = nil }, false},
		{"名前が50文字を超える SNS", func(r *rsResume) { r.SnsPlatforms[0].Name = ptr(strings.Repeat("s", 51)) }, false},
		{"https でないリンクの SNS", func(r *rsResume) { r.SnsPlatforms[0].Link = ptr("ftp://example.com") }, false},
		{"リンクの無い SNS", func(r *rsResume) { r.SnsPlatforms[0].Link = nil }, false},
		// 自己PR(SelfPromotion)
		{"題の無い自己PR", func(r *rsResume) { r.SelfPromotions[0].Title = nil }, false},
		{"題が50文字を超える自己PR", func(r *rsResume) { r.SelfPromotions[0].Title = ptr(strings.Repeat("題", 51)) }, false},
		{"中身が空白だけの自己PR", func(r *rsResume) { r.SelfPromotions[0].Content = ptr(" ") }, false},
		{"中身が1000文字を超える自己PR", func(r *rsResume) { r.SelfPromotions[0].Content = ptr(strings.Repeat("中", 1001)) }, false},
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

// TestBuildRestored_LaxRules は、利用者が画面で保存するときの決まりのうち、戻しが確かめない6つの決まりに当たる値を、
// buildRestored が断らないことを確かめる(要件4の受入基準5)。
func TestBuildRestored_LaxRules(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(r *rsResume)
	}{
		{"1900年から2100年の外の年月と日付", func(r *rsResume) {
			r.Date = dt(1800, 1, 1)
			r.Careers[0].StartDate, r.Careers[0].EndDate = ym(1899, 12), ym(2101, 1)
			r.Certifications[0].Date = ym(2200, 1)
		}},
		{"期間が重なる職歴", func(r *rsResume) {
			r.Careers = append(r.Careers, &rsCareer{
				CompanyName: ptr("株式会社二"), StartDate: ym(2012, 1), EndDate: ym(2018, 1),
			})
		}},
		{"255文字を超えるリンク", func(r *rsResume) {
			r.Portfolios[0].Link = ptr("https://example.com/" + strings.Repeat("a", 300))
			r.SnsPlatforms[0].Link = ptr("https://example.com/" + strings.Repeat("b", 300))
		}},
		{"姓と名の両方が無い経歴書", func(r *rsResume) { r.LastName, r.FirstName = nil, nil }},
		{"工程を1つも選んでいないプロジェクト", func(r *rsResume) { r.Projects[0].Process = bkProcess{} }},
		{"欄ごとの項目の数の上限を超える経歴書", func(r *rsResume) {
			r.Careers = repeatEntry(r.Careers[0], careerLimit.limit+1)
			r.Projects = repeatEntry(r.Projects[0], projectLimit.limit+1)
			r.Certifications = repeatEntry(r.Certifications[0], certificationLimit.limit+1)
			r.Portfolios = repeatEntry(r.Portfolios[0], portfolioLimit.limit+1)
			r.SnsPlatforms = repeatEntry(r.SnsPlatforms[0], snsPlatformLimit.limit+1)
			r.SelfPromotions = repeatEntry(r.SelfPromotions[0], selfPromotionLimit.limit+1)
		}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r := validRestore()
			c.mutate(r)
			if _, ok := buildRestored(r, restoreUser); !ok {
				t.Error("戻しが確かめない決まりに当たる値を断った")
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

// TestBuildRestored_Defaults は、ファイルの中に無い欄と値を、buildRestored が補うことを確かめる(要件2の受入基準2)。
// 本文は readRestoreFile で読み、読んだ経歴書を buildRestored に渡す。
func TestBuildRestored_Defaults(t *testing.T) {
	restore := func(t *testing.T, resume string) Resume {
		t.Helper()
		f, ok := readRestoreFile([]byte(`{"version":"1.0","resume":` + resume + `}`))
		if !ok || f.Resume == nil {
			t.Fatalf("本文を読めない: %s", resume)
		}
		got, ok := buildRestored(f.Resume, restoreUser)
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
		if p := got.Projects[0]; p.Process != (Process{}) || !reflect.DeepEqual(p.TechStack, emptyStacks()) {
			t.Errorf("工程 = %+v、技術 = %+v。want 選んでいないもの", p.Process, p.TechStack)
		}
	})
}

// TestBuildRestored_SortsEntries は、buildRestored が、6つの欄の項目を、経歴書を読み出すときと同じ sortEntries の順に並べることを
// 確かめる(要件2の受入基準1)。
func TestBuildRestored_SortsEntries(t *testing.T) {
	r := validRestore()
	career := func(name string, start, end jsonYearMonth) *rsCareer {
		return &rsCareer{CompanyName: ptr(name), StartDate: start, EndDate: end, Active: !end.Present}
	}
	r.Careers = []*rsCareer{
		career("古い会社", ym(2010, 4), ym(2012, 3)),
		career("今の会社", ym(2015, 4), jsonYearMonth{}),
		career("中の会社", ym(2013, 4), ym(2014, 3)),
	}
	project := func(name string, start jsonYearMonth) *rsProject {
		p := *r.Projects[0]
		p.Name, p.StartDate = ptr(name), start
		return &p
	}
	r.Projects = []*rsProject{project("中の案件", ym(2016, 1)), project("古い案件", ym(2014, 1)), project("新しい案件", ym(2020, 1))}
	r.Certifications = []*rsCertification{
		{Name: ptr("古い資格"), Date: ym(2010, 1)},
		{Name: ptr("新しい資格"), Date: ym(2020, 1)},
		{Name: ptr("中の資格"), Date: ym(2015, 1)},
	}
	portfolio := func(name string) *rsPortfolio {
		return &rsPortfolio{Name: ptr(name), Overview: ptr("説明"), Link: ptr("https://example.com")}
	}
	r.Portfolios = []*rsPortfolio{portfolio("う作品"), portfolio("あ作品"), portfolio("い作品")}
	r.SnsPlatforms = []*rsSnsPlatform{
		{Name: ptr("Zenn"), Link: ptr("https://zenn.dev")},
		{Name: ptr("GitHub"), Link: ptr("https://github.com")},
		{Name: ptr("Qiita"), Link: ptr("https://qiita.com")},
	}
	r.SelfPromotions = []*rsSelfPromotion{{Title: ptr("C 題"), Content: ptr("中身")}, {Title: ptr("A 題"), Content: ptr("中身")}, {Title: ptr("B 題"), Content: ptr("中身")}}

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
