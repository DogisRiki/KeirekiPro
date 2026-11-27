package resume

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// restoreLimitUser は、経歴書を上限の50件持つ resumes/resume-limits.sql の利用者である。
var restoreLimitUser = uuid.MustParse("00000000-0000-4000-8000-000000000500")

// restoreFile は、Java 版が戻しで確かめる値の決まりをすべて満たす、6つの欄に1件ずつ項目を持つ戻しの本文の値を返す。
// mutate が nil でなければ、mutate で本文の値を変えてから返す。
func restoreFile(mutate func(file, resume map[string]any)) map[string]any {
	resume := map[string]any{
		"resumeName": "戻す経歴書", "date": "2026-02-05", "lastName": "高橋", "firstName": "次郎",
		"careers": []any{
			map[string]any{"companyName": "株式会社もどす", "startDate": "2016-04", "endDate": "2020-03", "active": false},
		},
		"projects": []any{map[string]any{
			"companyName": "株式会社もどす", "startDate": "2016-04", "endDate": "2019-09", "active": false,
			"name": "在庫の管理の画面の開発", "overview": "概要", "teamComp": "全体6名", "role": "実装", "achievement": "成果",
			"process": map[string]any{"basicDesign": true, "implementation": true},
		}},
		"certifications": []any{map[string]any{"name": "基本情報技術者", "date": "2015-10"}},
		"portfolios": []any{
			map[string]any{"name": "作品", "overview": "説明", "techStack": "Go", "link": "https://example.com/works"},
		},
		"snsPlatforms":   []any{map[string]any{"name": "GitHub", "link": "https://github.com/restore"}},
		"selfPromotions": []any{map[string]any{"title": "題", "content": "中身"}},
	}
	file := map[string]any{"version": "1.0", "exportedAt": "2026-02-05T01:00:00Z", "resume": resume}
	if mutate != nil {
		mutate(file, resume)
	}
	return file
}

// endBeforeStart は、職歴の終わりの年月を始まりの年月より前にして、本文を値の決まりを満たさないものにする。
func endBeforeStart(_, resume map[string]any) {
	resume["careers"] = []any{
		map[string]any{"companyName": "株式会社もどす", "startDate": "2016-04", "endDate": "2016-03", "active": false},
	}
}

// TestRestoreIntegration_Order は、戻しが、Java 版と同じく、本文、値の無い要素を持つ欄、ファイルの版、経歴書の数、経歴書の中身、
// 名前の重なり、値の決まりの順に確かめ、2つ以上の条件に当たる要求が順の早い条件の誤りになることを確かめる
// (要件4の受入基準1と3と4)。
func TestRestoreIntegration_Order(t *testing.T) {
	loadBackupFixtures(t)
	svc := New(Deps{Pool: testPool})
	user := insertTestUser(t)
	dupUser := insertTestUser(t)
	saveResume(t, emptyResume(dupUser, "重なる経歴書"))
	// Java 版の名前の重なりは、名前の値の決まりより先に確かめるので、使えない字を含む名前も重なる
	saveResume(t, emptyResume(dupUser, "経歴書/一"))

	unsupported := auth.ErrBusiness(MessageUnsupportedBackupVersion)
	invalid := auth.ErrBusiness(MessageInvalidBackupFile)
	limit := resumeLimit.check(resumeLimit.limit)
	cases := []struct {
		name   string
		userID uuid.UUID
		body   []byte
		want   error
	}{
		{"読めない本文は、上限の利用者でも本文の誤り", restoreLimitUser, []byte(`{"version":`), errUnreadableInput()},
		{"値の無い要素を持つ欄は、版の誤りより先", user, jsonBody(t, restoreFile(func(f, r map[string]any) {
			f["version"] = "2.0"
			r["careers"] = []any{nil}
		})), errRestoreServer},
		{"版の誤りは、経歴書の数の上限より先", restoreLimitUser, jsonBody(t, restoreFile(func(f, _ map[string]any) {
			f["version"] = "2.0"
		})), unsupported},
		{"版の無いファイルは版の誤り", user, jsonBody(t, restoreFile(func(f, _ map[string]any) {
			delete(f, "version")
		})), unsupported},
		{"版の誤りは、経歴書の中身が無いことより先", user, jsonBody(t, restoreFile(func(f, _ map[string]any) {
			f["version"], f["resume"] = "1.1", nil
		})), unsupported},
		{"経歴書の数の上限", restoreLimitUser, jsonBody(t, restoreFile(nil)), limit},
		{"経歴書の数の上限は、経歴書の中身が無いことより先", restoreLimitUser, jsonBody(t, restoreFile(func(f, _ map[string]any) {
			delete(f, "resume")
		})), limit},
		{"経歴書の数の上限は、名前の重なりと値の決まりより先", restoreLimitUser, jsonBody(t, restoreFile(func(f, r map[string]any) {
			r["resumeName"] = "上限の経歴書01"
			endBeforeStart(f, r)
		})), limit},
		{"経歴書の中身が無いファイル", user, jsonBody(t, restoreFile(func(f, _ map[string]any) {
			delete(f, "resume")
		})), errRestoreServer},
		{"名前の重なり", dupUser, jsonBody(t, restoreFile(func(_, r map[string]any) {
			r["resumeName"] = "重なる経歴書"
		})), errResumeNameDuplicated()},
		{"名前の重なりは、値の決まりより先", dupUser, jsonBody(t, restoreFile(func(f, r map[string]any) {
			r["resumeName"] = "重なる経歴書"
			endBeforeStart(f, r)
		})), errResumeNameDuplicated()},
		{"名前の重なりは、名前の値の決まりより先", dupUser, jsonBody(t, restoreFile(func(_, r map[string]any) {
			r["resumeName"] = "経歴書/一"
		})), errResumeNameDuplicated()},
		{"名前の無いファイルは、名前の重なりを確かめずに値の決まりの誤り", dupUser, jsonBody(t, restoreFile(func(_, r map[string]any) {
			delete(r, "resumeName")
		})), invalid},
		{"値の決まりを満たさないファイル", user, jsonBody(t, restoreFile(endBeforeStart)), invalid},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := svc.RestoreResume(t.Context(), c.userID, c.body)
			if want, ok := c.want.(*auth.Error); ok {
				assertError(t, c.name, err, want)
			} else if !errors.Is(err, c.want) {
				t.Errorf("誤り: got %#v, want %#v", err, c.want)
			}
			if got.ID != uuid.Nil {
				t.Errorf("誤りのときに経歴書を返した: %+v", got)
			}
		})
	}
	if n := countUserResumes(t, user); n != 0 {
		t.Errorf("断った要求のあとの経歴書の数 = %d。want 0", n)
	}
	if n := countUserResumes(t, dupUser); n != 2 {
		t.Errorf("断った要求のあとの経歴書の数 = %d。want 2", n)
	}
}

// TestRestoreIntegration_Owner は、戻した経歴書が要求を送った利用者の経歴書になり、ほかの利用者からは無い経歴書になることと、
// データベースに入れた経歴書と答えの経歴書が同じことを確かめる(要件2の受入基準3)。
func TestRestoreIntegration_Owner(t *testing.T) {
	loadBackupFixtures(t)
	now := japanTime(2026, time.November, 24, 12, 34, 56, 789_000)
	svc := New(Deps{Pool: testPool, Now: fixedNow(now)})
	owner := insertTestUser(t)
	other := insertTestUser(t)

	got, err := svc.RestoreResume(t.Context(), owner, jsonBody(t, restoreFile(nil)))
	if err != nil {
		t.Fatalf("戻せません: %v", err)
	}
	if got.UserID != owner || got.Name != "戻す経歴書" || !got.CreatedAt.Equal(now) || !got.UpdatedAt.Equal(now) {
		t.Errorf("利用者 = %s、名前 = %q、作った日時 = %v、直した日時 = %v。want %s、戻す経歴書、%v、%v",
			got.UserID, got.Name, got.CreatedAt, got.UpdatedAt, owner, now, now)
	}
	stored := mustGetResume(t, owner, got.ID.String())
	if !reflect.DeepEqual(stored, got) {
		t.Errorf("データベースの経歴書が答えと違う:\n  db %+v\ngot %+v", stored, got)
	}
	if _, err := svc.GetResume(t.Context(), other, got.ID.String()); err == nil {
		t.Error("ほかの利用者が戻した経歴書を読めた")
	} else {
		assertResumeNotFound(t, err)
	}
	if n := countUserResumes(t, owner); n != 1 {
		t.Errorf("持ち主の経歴書の数 = %d。want 1", n)
	}
	if n := countUserResumes(t, other); n != 0 {
		t.Errorf("ほかの利用者の経歴書の数 = %d。want 0", n)
	}
}

// TestRestoreIntegration_NoLeftover は、値の決まりを満たさない要求と、データベースの列の長さを超える値の要求のあとに、
// 経歴書と項目の行の数が変わらないことを確かめる(要件4の受入基準1)。
func TestRestoreIntegration_NoLeftover(t *testing.T) {
	loadBackupFixtures(t)
	svc := New(Deps{Pool: testPool})
	user := insertTestUser(t)
	cases := []struct {
		name    string
		mutate  func(file, resume map[string]any)
		authErr bool
	}{
		{"値の決まりを満たさない要求", endBeforeStart, true},
		// ポートフォリオの link の列は 255 字までで、経歴書と職歴とプロジェクトと資格の行を入れたあとに断られる
		{"データベースの列の長さを超える値の要求", func(_, r map[string]any) {
			r["portfolios"] = []any{map[string]any{
				"name": "作品", "overview": "説明", "link": "https://example.com/" + strings.Repeat("a", 300),
			}}
		}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			before := countAllResumeRows(t)
			_, err := svc.RestoreResume(t.Context(), user, jsonBody(t, restoreFile(c.mutate)))
			var ae *auth.Error
			if err == nil || errors.As(err, &ae) != c.authErr {
				t.Errorf("誤り = %#v。want 400 の誤りか = %v", err, c.authErr)
			}
			if after := countAllResumeRows(t); after != before {
				t.Errorf("断った要求のあとの行の数 = %d。want %d", after, before)
			}
			if n := countUserResumes(t, user); n != 0 {
				t.Errorf("断った要求のあとの経歴書の数 = %d。want 0", n)
			}
		})
	}
}

// countAllResumeRows は、経歴書の表と、6つの欄の項目の表と、プロジェクトの技術スタックの表の行を合わせた数を返す。
func countAllResumeRows(t *testing.T) int {
	t.Helper()
	var n int
	if err := testPool.QueryRow(t.Context(), `
		SELECT (SELECT count(*) FROM resumes) + (SELECT count(*) FROM careers) + (SELECT count(*) FROM projects)
		     + (SELECT count(*) FROM project_tech_stacks) + (SELECT count(*) FROM certifications)
		     + (SELECT count(*) FROM portfolios) + (SELECT count(*) FROM sns_platforms) + (SELECT count(*) FROM self_promotions)`,
	).Scan(&n); err != nil {
		t.Fatalf("行を数えられません: %v", err)
	}
	return n
}

// restoreJavaCase は、testdata/backup/restore.json に控えた、戻しの本文の1つと、Java 版の答えである。
type restoreJavaCase struct {
	Name        string `json:"name"`
	Body        string `json:"body"`
	Status      int    `json:"status"`
	Response    string `json:"response"`
	SendTwice   bool   `json:"send_twice"`
	FirstStatus int    `json:"first_status"`
}

// readRestoreJavaCases は、testdata/backup/restore.json の本文と答えを、控えた順に返す。控えた本文と答えは、
// 対になっていないサロゲートを、本文と答えの JSON の字の中の番号の書き方で持つので、encoding/json で読んでも字が変わらない。
func readRestoreJavaCases(t *testing.T) []restoreJavaCase {
	t.Helper()
	raw, err := os.ReadFile("testdata/backup/restore.json")
	if err != nil {
		t.Fatal(err)
	}
	var file struct {
		Cases []restoreJavaCase `json:"cases"`
	}
	if err := json.Unmarshal(raw, &file); err != nil {
		t.Fatal(err)
	}
	return file.Cases
}

// restoredView は、戻した経歴書の答えの本文から、経歴書と項目の ID と、作った日時と直した日時を除いた形である。
// 欄の名前と、値の無いときの書き方は、経歴書1件の取得の答え(internal/httpapi の resumeBody)と同じである。Java 版は、
// 戻しの答えに、経歴書1件の取得と同じ形を使う。工程は、testdata/backup/restore.json に控えた Java 版の答えと比べるので、
// Java 版と同じく、maintenance の鍵に SystemTest の値を、systemTest の鍵に Maintenance の値を入れる。Go 版の resumeBody は、
// 2つの値を入れ替えない(変えた動きの一覧の CB-078)。
type restoredView struct {
	ResumeName     string                      `json:"resumeName"`
	Date           string                      `json:"date"`
	LastName       *string                     `json:"lastName,omitempty"`
	FirstName      *string                     `json:"firstName,omitempty"`
	Careers        []restoredCareerView        `json:"careers,omitempty"`
	Projects       []restoredProjectView       `json:"projects,omitempty"`
	Certifications []restoredCertificationView `json:"certifications,omitempty"`
	Portfolios     []restoredPortfolioView     `json:"portfolios,omitempty"`
	SnsPlatforms   []restoredSnsPlatformView   `json:"snsPlatforms,omitempty"`
	SelfPromotions []restoredSelfPromotionView `json:"selfPromotions,omitempty"`
}

type restoredCareerView struct {
	CompanyName string  `json:"companyName"`
	StartDate   string  `json:"startDate"`
	EndDate     *string `json:"endDate"`
	Active      bool    `json:"active"`
}

type restoredProjectView struct {
	CompanyName string              `json:"companyName"`
	StartDate   string              `json:"startDate"`
	EndDate     *string             `json:"endDate"`
	Active      bool                `json:"active"`
	Name        string              `json:"name"`
	Overview    string              `json:"overview"`
	TeamComp    string              `json:"teamComp"`
	Role        string              `json:"role"`
	Achievement string              `json:"achievement"`
	Process     restoredProcessView `json:"process"`
	TechStack   TechStack           `json:"techStack"`
}

type restoredProcessView struct {
	Requirements    bool `json:"requirements"`
	BasicDesign     bool `json:"basicDesign"`
	DetailedDesign  bool `json:"detailedDesign"`
	Implementation  bool `json:"implementation"`
	IntegrationTest bool `json:"integrationTest"`
	Maintenance     bool `json:"maintenance"`
	SystemTest      bool `json:"systemTest"`
}

type restoredCertificationView struct {
	Name string `json:"name"`
	Date string `json:"date"`
}

type restoredPortfolioView struct {
	Name      string  `json:"name"`
	Overview  string  `json:"overview"`
	TechStack *string `json:"techStack"`
	Link      string  `json:"link"`
}

type restoredSnsPlatformView struct {
	Name string `json:"name"`
	Link string `json:"link"`
}

type restoredSelfPromotionView struct {
	Title   string `json:"title"`
	Content string `json:"content"`
}

// viewYearMonth は、年月を Java の YearMonth と同じ yyyy-MM で書く。
func viewYearMonth(ym YearMonth) string {
	return fmt.Sprintf("%04d-%02d", ym.Year, int(ym.Month))
}

// viewEndDate は、終わりの年月が無ければ nil を、あれば viewYearMonth で書いた字を返す。
func viewEndDate(ym *YearMonth) *string {
	if ym == nil {
		return nil
	}
	s := viewYearMonth(*ym)
	return &s
}

// newRestoredView は、戻した経歴書 r を、答えの本文の形にする。
func newRestoredView(r Resume) restoredView {
	v := restoredView{
		ResumeName: r.Name,
		Date:       fmt.Sprintf("%04d-%02d-%02d", r.Date.Year, int(r.Date.Month), r.Date.Day),
		LastName:   r.LastName,
		FirstName:  r.FirstName,
	}
	for _, c := range r.Careers {
		v.Careers = append(v.Careers, restoredCareerView{
			CompanyName: c.CompanyName, StartDate: viewYearMonth(c.Period.StartDate), EndDate: viewEndDate(c.Period.EndDate),
			Active: c.Period.Active,
		})
	}
	for _, p := range r.Projects {
		v.Projects = append(v.Projects, restoredProjectView{
			CompanyName: p.CompanyName, StartDate: viewYearMonth(p.Period.StartDate), EndDate: viewEndDate(p.Period.EndDate),
			Active: p.Period.Active, Name: p.Name, Overview: p.Overview, TeamComp: p.TeamComp, Role: p.Role,
			Achievement: p.Achievement,
			Process: restoredProcessView{
				Requirements: p.Process.Requirements, BasicDesign: p.Process.BasicDesign,
				DetailedDesign: p.Process.DetailedDesign, Implementation: p.Process.Implementation,
				IntegrationTest: p.Process.IntegrationTest, Maintenance: p.Process.SystemTest, SystemTest: p.Process.Maintenance,
			},
			TechStack: p.TechStack,
		})
	}
	for _, c := range r.Certifications {
		v.Certifications = append(v.Certifications, restoredCertificationView{Name: c.Name, Date: viewYearMonth(c.Date)})
	}
	for _, p := range r.Portfolios {
		v.Portfolios = append(v.Portfolios, restoredPortfolioView{
			Name: p.Name, Overview: p.Overview, TechStack: p.TechStack, Link: p.Link,
		})
	}
	for _, s := range r.SnsPlatforms {
		v.SnsPlatforms = append(v.SnsPlatforms, restoredSnsPlatformView{Name: s.Name, Link: s.Link})
	}
	for _, s := range r.SelfPromotions {
		v.SelfPromotions = append(v.SelfPromotions, restoredSelfPromotionView{Title: s.Title, Content: s.Content})
	}
	return v
}

// restoredSections は、答えの本文の、項目の並びを持つ6つの欄の名前である。
var restoredSections = []string{"careers", "projects", "certifications", "portfolios", "snsPlatforms", "selfPromotions"}

// withoutRestoredIDs は、Java 版の 201 の答えの本文の値の木 v から、経歴書の id と createdAt と updatedAt の欄と、
// 6つの欄の項目の id の欄を除く。
func withoutRestoredIDs(v *jv) *jv {
	drop := func(o *jv, names ...string) *jv {
		out := &jv{kind: jvObject}
		for _, m := range o.members {
			if !slices.Contains(names, m.name) {
				out.members = append(out.members, m)
			}
		}
		return out
	}
	out := drop(v, "id", "createdAt", "updatedAt")
	for i, m := range out.members {
		if !slices.Contains(restoredSections, m.name) || m.value.kind != jvArray {
			continue
		}
		items := &jv{kind: jvArray}
		for _, item := range m.value.items {
			items.items = append(items.items, drop(item, "id"))
		}
		out.members[i] = jvMember{name: m.name, value: items}
	}
	return out
}

// assertRestoreAnswer は、Go 版の戻しの答え got と err が、Java 版の答え c と同じことを確かめる。
// 誤りが *auth.Error なら、状態の番号と文言と項目ごとの文言を確かめる。誤りが *auth.Error でなければ、Java 版が 500 で
// 答えたことを確かめる。500 の本文は、置き換えの spec の土台の誤りの受け口が書くので、比べない。誤りが無ければ、
// Java 版が 201 で答えたことと、経歴書と項目の ID と作った日時と直した日時を除いた答えの本文が、JSON として読んだ値で
// 同じことを確かめる。
func assertRestoreAnswer(t *testing.T, c restoreJavaCase, got Resume, err error) {
	t.Helper()
	java := mustParseJTree(t, c.Response)
	var ae *auth.Error
	switch {
	case err == nil:
		if c.Status != 201 {
			t.Errorf("%s: Go 版は経歴書を戻した。Java 版の答えは %d %s", c.Name, c.Status, c.Response)
			return
		}
		want := dumpJV(withoutRestoredIDs(java))
		if body := dumpJV(mustParseJTree(t, string(JavaJSON(newRestoredView(got))))); body != want {
			t.Errorf("%s: 答えの本文が Java 版と違う:\n  go   %s\n  java %s", c.Name, body, want)
		}
	case errors.As(err, &ae):
		want := `{"errors":{},"message":` + dumpJV(&jv{kind: jvString, text: ae.Message}) + `}`
		if c.Status != ae.Status || dumpJV(java) != want || len(ae.Errors) != 0 {
			t.Errorf("%s: Go 版の答えは %d %q %v。Java 版の答えは %d %s", c.Name, ae.Status, ae.Message, ae.Errors, c.Status, c.Response)
		}
	default:
		if c.Status != 500 {
			t.Errorf("%s: Go 版の答えは 500 の誤り %v。Java 版の答えは %d %s", c.Name, err, c.Status, c.Response)
		}
	}
}

// deleteRestored は、戻しで作った利用者 userID の経歴書 r を消す。
func deleteRestored(t *testing.T, svc *Service, userID uuid.UUID, r Resume) {
	t.Helper()
	if err := svc.DeleteResume(context.Background(), userID, r.ID.String()); err != nil {
		t.Fatalf("戻した経歴書を消せません: %v", err)
	}
}

// TestRestoreIntegration_MatchesJava は、testdata/backup/restore.json の本文ごとに、Go 版の答えの状態の番号と文言と、
// 201 の答えの本文が、Java 版の答えと同じことを確かめる(要件2の受入基準1と2、要件4の受入基準2と5と6、
// 要件1の受入基準1のうち形の誤ったファイルへの答え)。答えを控えたときと同じく、経歴書を持たない user2 で本文を順に戻し、
// 答えが 201 のときは、次の本文を戻す前に、作られた経歴書を消す。2回続けて戻す本文は、TestRestoreIntegration_SurrogateName が確かめる。
func TestRestoreIntegration_MatchesJava(t *testing.T) {
	loadBackupFixtures(t)
	svc := New(Deps{Pool: testPool})
	if n := countUserResumes(t, exportUser2); n != 0 {
		t.Fatalf("user2 の経歴書の数 = %d。want 0", n)
	}
	compared := 0
	for _, c := range readRestoreJavaCases(t) {
		if c.SendTwice {
			continue
		}
		t.Run(c.Name, func(t *testing.T) {
			got, err := svc.RestoreResume(t.Context(), exportUser2, []byte(c.Body))
			if err == nil {
				deleteRestored(t, svc, exportUser2, got)
			}
			assertRestoreAnswer(t, c, got, err)
		})
		compared++
	}
	if compared != 422 {
		t.Errorf("比べた本文の数 = %d。want 422", compared)
	}
	if n := countUserResumes(t, exportUser2); n != 0 {
		t.Errorf("比べ終えたあとの user2 の経歴書の数 = %d。want 0", n)
	}
}

// TestRestoreIntegration_SurrogateName は、名前に対になっていないサロゲートを含むファイルを、そのサロゲートを ? にした名前の
// 経歴書を持つ利用者が戻すと、名前の重なりの誤りにならず、restore.json に控えた Java 版の答えと同じ答えになることを確かめる
// (要件1の受入基準1、要件4の受入基準4)。答えを控えたときと同じく、このファイルを user2 で2回続けて戻し、2回目の答えを比べる。
func TestRestoreIntegration_SurrogateName(t *testing.T) {
	loadBackupFixtures(t)
	svc := New(Deps{Pool: testPool})
	var c restoreJavaCase
	for _, cc := range readRestoreJavaCases(t) {
		if cc.SendTwice {
			c = cc
		}
	}
	if c.FirstStatus != 201 {
		t.Fatalf("2回続けて戻す本文の1回目の Java 版の答え = %d。want 201", c.FirstStatus)
	}
	first, err := svc.RestoreResume(t.Context(), exportUser2, []byte(c.Body))
	if err != nil {
		t.Fatalf("1回目の戻し: %v", err)
	}
	t.Cleanup(func() { deleteRestored(t, svc, exportUser2, first) })
	// 1回目の戻しで、データベースに、名前のサロゲートを ? にした経歴書ができる
	if stored := mustGetResume(t, exportUser2, first.ID.String()).Name; stored == first.Name || stored != toDBText(first.Name) {
		t.Fatalf("データベースの経歴書の名前 = %q。want %q", stored, toDBText(first.Name))
	}
	got, err := svc.RestoreResume(t.Context(), exportUser2, []byte(c.Body))
	if err == nil {
		t.Cleanup(func() { deleteRestored(t, svc, exportUser2, got) })
	}
	assertRestoreAnswer(t, c, got, err)
}

// TestRestoreIntegration_DeletedUser は、退会してすでに居ない利用者の要求のうち、変えた動きの一覧の CB-063 から CB-066 の
// 4つの戻しが 404 と「対象の職務経歴書データが存在しません。」になり、版の誤りと読めない本文と値の決まりを満たさない本文が、
// 利用者が居るときと同じ 400 になることを確かめる(要件5の受入基準3)。
func TestRestoreIntegration_DeletedUser(t *testing.T) {
	loadBackupFixtures(t)
	svc := New(Deps{Pool: testPool})
	user := insertTestUser(t)
	if _, err := testPool.Exec(t.Context(), `DELETE FROM users WHERE id = $1::uuid`, user.String()); err != nil {
		t.Fatalf("退会した利用者の行を消せません: %v", err)
	}
	const linkPrefix = "https://example.com/"
	cases := []struct {
		name string
		body []byte
		want *auth.Error
	}{
		{"CB-063 版の正しいファイル", jsonBody(t, restoreFile(nil)), errResumeNotFound()},
		{"CB-064 項目の並びに値の無い要素を持つファイル", jsonBody(t, restoreFile(func(_, r map[string]any) {
			r["careers"] = []any{nil}
		})), errResumeNotFound()},
		{"CB-065 経歴書の中身が無いファイル", jsonBody(t, restoreFile(func(f, _ map[string]any) {
			delete(f, "resume")
		})), errResumeNotFound()},
		{"CB-066 256文字のリンクを持つファイル", jsonBody(t, restoreFile(func(_, r map[string]any) {
			r["portfolios"] = []any{map[string]any{
				"name": "作品", "overview": "説明", "link": linkPrefix + strings.Repeat("a", 256-len(linkPrefix)),
			}}
		})), errResumeNotFound()},
		{"版の誤り", jsonBody(t, restoreFile(func(f, _ map[string]any) {
			f["version"] = "2.0"
		})), auth.ErrBusiness(MessageUnsupportedBackupVersion)},
		{"読めない本文", []byte(`{"version":`), errUnreadableInput()},
		{"値を読めない本文", jsonBody(t, restoreFile(func(_, r map[string]any) {
			r["date"] = "not-a-date"
		})), errUnreadableInput()},
		{"値の決まりを満たさない本文", jsonBody(t, restoreFile(endBeforeStart)), auth.ErrBusiness(MessageInvalidBackupFile)},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := svc.RestoreResume(t.Context(), user, c.body)
			assertError(t, c.name, err, c.want)
			if got.ID != uuid.Nil {
				t.Errorf("誤りのときに経歴書を返した: %+v", got)
			}
		})
	}
}
