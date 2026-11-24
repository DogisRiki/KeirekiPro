package resume

import (
	"encoding/json"
	"errors"
	"reflect"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
)

// insertTestUser は、経歴書の持ち主になる利用者の行を足し、利用者の ID を返す。resumes.user_id は users を参照するためである。
func insertTestUser(t *testing.T) uuid.UUID {
	t.Helper()
	id := uuid.New()
	if _, err := testPool.Exec(t.Context(),
		`INSERT INTO users (id, created_at, updated_at) VALUES ($1::uuid, now(), now())`, id.String()); err != nil {
		t.Fatalf("利用者の行を足せません: %v", err)
	}
	return id
}

// testStore は、テストの Postgres の接続の束の上の store である。
func testStore() store {
	return poolStore(testPool)
}

// japanTime は、日本の時刻の見た目の時刻を作る。
func japanTime(y int, mo time.Month, d, h, mi, s, ns int) time.Time {
	return time.Date(y, mo, d, h, mi, s, ns, japanZone)
}

// fullResume は、6つの欄の項目を2つずつ持つ経歴書を作る。技術スタックは、NULL の要素と、TEXT[] の書き方で特別な意味を持つ文字を
// 含む名前と、空の並びと、並びが無い小分類を持つ。期間は、継続中のものと終了の年月を持つものを持つ。
func fullResume(userID uuid.UUID) Resume {
	special := "a,b \"c\" \\d {e} NULL"
	tech := TechStack{}
	tech.Frontend.Languages = []*string{ptr("TypeScript"), nil, ptr(special)}
	tech.Frontend.Frameworks = []*string{}
	tech.Backend.Auth = []*string{ptr("NULL"), ptr("")}
	tech.Infrastructure.Databases = []*string{ptr("PostgreSQL")}
	tech.Tools.DevelopmentEnvironments = []*string{nil}
	return Resume{
		ID:        uuid.New(),
		UserID:    userID,
		Name:      "経歴書",
		Date:      Date{Year: 2026, Month: time.November, Day: 14},
		LastName:  ptr("山田"),
		FirstName: nil,
		CreatedAt: japanTime(2026, time.November, 14, 10, 23, 45, 123456000),
		UpdatedAt: japanTime(2026, time.November, 15, 11, 0, 0, 0),
		Careers: []Career{
			{ID: uuid.New(), CompanyName: "株式会社A", Period: Period{StartDate: YearMonth{2020, time.April}, Active: true}},
			{ID: uuid.New(), CompanyName: "株式会社B", Period: Period{StartDate: YearMonth{2015, time.April}, EndDate: yearMonth(2020, time.March)}},
		},
		Projects: []Project{
			{
				ID: uuid.New(), CompanyName: "株式会社A", Period: Period{StartDate: YearMonth{2021, time.January}, Active: true},
				Name: "案件1", Overview: "概要", TeamComp: "5名", Role: "リーダー", Achievement: "成果",
				Process:   Process{Requirements: true, SystemTest: true},
				TechStack: tech,
			},
			{
				ID: uuid.New(), CompanyName: "株式会社B", Period: Period{StartDate: YearMonth{2016, time.May}, EndDate: yearMonth(2019, time.December)},
				Name: "案件2", Overview: "概要2", TeamComp: "3名", Role: "開発", Achievement: "成果2",
				Process: Process{BasicDesign: true, DetailedDesign: true, Implementation: true, IntegrationTest: true, Maintenance: true},
			},
		},
		Certifications: []Certification{
			{ID: uuid.New(), Name: "基本情報技術者", Date: YearMonth{2018, time.October}},
			{ID: uuid.New(), Name: "応用情報技術者", Date: YearMonth{2019, time.April}},
		},
		Portfolios: []Portfolio{
			{ID: uuid.New(), Name: "ポートフォリオ1", Overview: "概要", TechStack: ptr("Go"), Link: "https://example.com/1"},
			{ID: uuid.New(), Name: "ポートフォリオ2", Overview: "概要2", TechStack: nil, Link: "https://example.com/2"},
		},
		SnsPlatforms: []SnsPlatform{
			{ID: uuid.New(), Name: "GitHub", Link: "https://github.com/example"},
			{ID: uuid.New(), Name: "Zenn", Link: "https://zenn.dev/example"},
		},
		SelfPromotions: []SelfPromotion{
			{ID: uuid.New(), Title: "強み", Content: "内容"},
			{ID: uuid.New(), Title: "弱み", Content: "内容2"},
		},
	}
}

// sorted は、経歴書の項目を、読み直したときと同じ順に並べた写しを返す。
func sorted(r Resume) Resume {
	r.Careers = slicesClone(r.Careers)
	r.Projects = slicesClone(r.Projects)
	r.Certifications = slicesClone(r.Certifications)
	r.Portfolios = slicesClone(r.Portfolios)
	r.SnsPlatforms = slicesClone(r.SnsPlatforms)
	r.SelfPromotions = slicesClone(r.SelfPromotions)
	sortEntries(&r)
	return r
}

// slicesClone は、並びの写しを返す。並びが空でも nil にしない。読み直した経歴書の項目の並びは、空でも nil にならないためである。
func slicesClone[E any](s []E) []E {
	return append(make([]E, 0, len(s)), s...)
}

// mustFind は、経歴書を読み直す。経歴書が無ければテストを止める。
func mustFind(t *testing.T, userID, resumeID uuid.UUID) Resume {
	t.Helper()
	got, found, err := testStore().findResume(t.Context(), userID, resumeID)
	if err != nil {
		t.Fatalf("経歴書を読めません: %v", err)
	}
	if !found {
		t.Fatalf("経歴書 %s が無い", resumeID)
	}
	return got
}

// assertResume は、読み直した経歴書が want と同じ値であることを確かめる。日時は、同じ時刻であることと、日本の時刻の見た目であることを確かめる。
func assertResume(t *testing.T, got, want Resume) {
	t.Helper()
	for _, c := range []struct {
		name      string
		got, want time.Time
	}{{"作成の日時", got.CreatedAt, want.CreatedAt}, {"更新の日時", got.UpdatedAt, want.UpdatedAt}} {
		if !c.got.Equal(c.want) || c.got.Location() != japanZone {
			t.Errorf("%s: got %v(%v), want %v(日本の時刻)", c.name, c.got, c.got.Location(), c.want)
		}
	}
	got.CreatedAt, got.UpdatedAt = time.Time{}, time.Time{}
	want.CreatedAt, want.UpdatedAt = time.Time{}, time.Time{}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("読み直した経歴書が違う\n got: %+v\nwant: %+v", got, want)
	}
}

// TestStore_RoundTrip は、経歴書と6つの欄の項目を書いて読み直すと同じ値になることと、Java 版と同じ表と値の形で書くことを確かめる(要件5の受入基準1)。
func TestStore_RoundTrip(t *testing.T) {
	userID := insertTestUser(t)
	r := fullResume(userID)
	if err := inTx(t.Context(), testPool, func(s store) error { return s.insertResume(t.Context(), r) }); err != nil {
		t.Fatalf("経歴書を書けません: %v", err)
	}

	t.Run("書いた経歴書を読み直すと同じ値になる", func(t *testing.T) {
		assertResume(t, mustFind(t, userID, r.ID), sorted(r))
	})

	t.Run("Java 版と同じ値の形で表に書く", func(t *testing.T) {
		var date, createdAt, startDate, endDate string
		var lastNameNull, firstNameNull, endDateNull, techNull bool
		if err := testPool.QueryRow(t.Context(),
			`SELECT date::text, created_at::text, last_name IS NULL, first_name IS NULL FROM resumes WHERE id = $1::uuid`,
			r.ID.String()).Scan(&date, &createdAt, &lastNameNull, &firstNameNull); err != nil {
			t.Fatalf("経歴書の行を読めません: %v", err)
		}
		if date != "2026-11-14" || createdAt != "2026-11-14 10:23:45.123456" || lastNameNull || !firstNameNull {
			t.Errorf("経歴書の行: date=%s created_at=%s last_name IS NULL=%v first_name IS NULL=%v", date, createdAt, lastNameNull, firstNameNull)
		}
		if err := testPool.QueryRow(t.Context(),
			`SELECT start_date::text, COALESCE(end_date::text, ''), end_date IS NULL FROM careers WHERE id = $1::uuid`,
			r.Careers[1].ID.String()).Scan(&startDate, &endDate, &endDateNull); err != nil {
			t.Fatalf("職歴の行を読めません: %v", err)
		}
		if startDate != "2015-04-01" || endDate != "2020-03-01" || endDateNull {
			t.Errorf("職歴の行: start_date=%s end_date=%s", startDate, endDate)
		}
		if err := testPool.QueryRow(t.Context(),
			`SELECT end_date IS NULL FROM careers WHERE id = $1::uuid`, r.Careers[0].ID.String()).Scan(&endDateNull); err != nil {
			t.Fatalf("職歴の行を読めません: %v", err)
		}
		if !endDateNull {
			t.Error("在籍中の職歴の end_date が NULL でない")
		}
		var languages, frameworks, authValues, devEnvs string
		var librariesNull bool
		if err := testPool.QueryRow(t.Context(),
			`SELECT frontend_languages::text, frontend_framework::text, frontend_libraries IS NULL, auth::text, development_environment::text
			 FROM project_tech_stacks WHERE project_id = $1::uuid`,
			r.Projects[0].ID.String()).Scan(&languages, &frameworks, &librariesNull, &authValues, &devEnvs); err != nil {
			t.Fatalf("技術スタックの行を読めません: %v", err)
		}
		if languages != `{TypeScript,NULL,"a,b \"c\" \\d {e} NULL"}` || frameworks != "{}" || !librariesNull ||
			authValues != `{"NULL",""}` || devEnvs != "{NULL}" {
			t.Errorf("技術スタックの行: frontend_languages=%s frontend_framework=%s frontend_libraries IS NULL=%v auth=%s development_environment=%s",
				languages, frameworks, librariesNull, authValues, devEnvs)
		}
		// 技術スタックを持たないプロジェクトにも、Java 版と同じく、すべての列が NULL の技術スタックの行を書く。
		if err := testPool.QueryRow(t.Context(),
			`SELECT frontend_languages IS NULL AND development_environment IS NULL FROM project_tech_stacks WHERE project_id = $1::uuid`,
			r.Projects[1].ID.String()).Scan(&techNull); err != nil {
			t.Fatalf("技術スタックの行を読めません: %v", err)
		}
		if !techNull {
			t.Error("技術スタックを持たないプロジェクトの技術スタックの列が NULL でない")
		}
	})

	t.Run("Java 版が書いた技術スタックの行が無いプロジェクトを読む", func(t *testing.T) {
		if _, err := testPool.Exec(t.Context(), `DELETE FROM project_tech_stacks WHERE project_id = $1::uuid`, r.Projects[1].ID.String()); err != nil {
			t.Fatalf("技術スタックの行を消せません: %v", err)
		}
		got := mustFind(t, userID, r.ID)
		for _, p := range got.Projects {
			if p.ID == r.Projects[1].ID && !reflect.DeepEqual(p.TechStack, TechStack{}) {
				t.Errorf("技術スタックの行が無いプロジェクトの技術スタック: %+v", p.TechStack)
			}
		}
		if err := inTx(t.Context(), testPool, func(s store) error {
			if _, err := s.deleteProject(t.Context(), r.ID, r.Projects[1].ID); err != nil {
				return err
			}
			return s.insertProject(t.Context(), r.ID, r.Projects[1])
		}); err != nil {
			t.Fatalf("プロジェクトを書き直せません: %v", err)
		}
	})

	t.Run("ほかの利用者は経歴書を読めない", func(t *testing.T) {
		other := insertTestUser(t)
		if _, found, err := testStore().findResume(t.Context(), other, r.ID); err != nil || found {
			t.Errorf("ほかの利用者の findResume: found=%v err=%v", found, err)
		}
		if _, found, err := testStore().findResume(t.Context(), userID, uuid.New()); err != nil || found {
			t.Errorf("無い経歴書の findResume: found=%v err=%v", found, err)
		}
		if err := inTx(t.Context(), testPool, func(s store) error {
			_, found, err := s.lockResume(t.Context(), other, r.ID)
			if found {
				t.Error("ほかの利用者の lockResume が経歴書を返した")
			}
			return err
		}); err != nil {
			t.Fatalf("lockResume: %v", err)
		}
	})

	t.Run("lockResume は経歴書の行に鍵をかけて読む", func(t *testing.T) {
		if err := inTx(t.Context(), testPool, func(s store) error {
			got, found, err := s.lockResume(t.Context(), userID, r.ID)
			if err != nil {
				return err
			}
			if !found {
				t.Fatal("lockResume が経歴書を返さない")
			}
			assertResume(t, got, sorted(r))
			// 別の接続から同じ行に鍵をかけようとすると、鍵を待たずに 55P03(lock_not_available)で断られる。
			_, err = testPool.Exec(t.Context(), `SELECT id FROM resumes WHERE id = $1::uuid FOR UPDATE NOWAIT`, r.ID.String())
			var pgErr *pgconn.PgError
			if !errors.As(err, &pgErr) || pgErr.Code != "55P03" {
				t.Errorf("lockResume のあとに別の接続から鍵をかけた結果: %v", err)
			}
			return nil
		}); err != nil {
			t.Fatalf("lockResume: %v", err)
		}
	})

	t.Run("項目を直して読み直すと同じ値になる", func(t *testing.T) {
		want := r
		want.Careers = slicesClone(r.Careers)
		want.Careers[1].CompanyName = "株式会社C"
		want.Careers[1].Period = Period{StartDate: YearMonth{2014, time.January}, Active: true}
		want.Projects = slicesClone(r.Projects)
		want.Projects[0].Name = "案件1改"
		want.Projects[0].Process = Process{Maintenance: true}
		want.Projects[0].TechStack = TechStack{}
		want.Projects[0].TechStack.Tools.Editors = []*string{ptr("Vim"), nil}
		want.Certifications = slicesClone(r.Certifications)
		want.Certifications[0].Date = YearMonth{2017, time.December}
		want.Portfolios = slicesClone(r.Portfolios)
		want.Portfolios[0].TechStack = nil
		want.Portfolios[1].TechStack = ptr("Rust")
		want.SnsPlatforms = slicesClone(r.SnsPlatforms)
		want.SnsPlatforms[0].Link = "https://github.com/other"
		want.SelfPromotions = slicesClone(r.SelfPromotions)
		want.SelfPromotions[1].Content = "直した内容"
		want.Name = "直した経歴書"
		want.Date = Date{Year: 2026, Month: time.December, Day: 1}
		want.LastName, want.FirstName = nil, ptr("太郎")
		want.UpdatedAt = japanTime(2026, time.December, 1, 9, 0, 0, 0)

		if err := inTx(t.Context(), testPool, func(s store) error {
			for _, update := range []func() (bool, error){
				func() (bool, error) { return s.updateCareer(t.Context(), r.ID, want.Careers[1]) },
				func() (bool, error) { return s.updateProject(t.Context(), r.ID, want.Projects[0]) },
				func() (bool, error) { return s.updateCertification(t.Context(), r.ID, want.Certifications[0]) },
				func() (bool, error) { return s.updatePortfolio(t.Context(), r.ID, want.Portfolios[0]) },
				func() (bool, error) { return s.updatePortfolio(t.Context(), r.ID, want.Portfolios[1]) },
				func() (bool, error) { return s.updateSnsPlatform(t.Context(), r.ID, want.SnsPlatforms[0]) },
				func() (bool, error) { return s.updateSelfPromotion(t.Context(), r.ID, want.SelfPromotions[1]) },
			} {
				found, err := update()
				if err != nil {
					return err
				}
				if !found {
					t.Error("直す項目が見つからない")
				}
			}
			return s.updateResumeBasic(t.Context(), want)
		}); err != nil {
			t.Fatalf("項目を直せません: %v", err)
		}
		assertResume(t, mustFind(t, userID, r.ID), sorted(want))
		r = want
	})

	t.Run("別の経歴書の項目は直さず消さない", func(t *testing.T) {
		other := fullResume(userID)
		other.Name = "別の経歴書"
		if err := inTx(t.Context(), testPool, func(s store) error { return s.insertResume(t.Context(), other) }); err != nil {
			t.Fatalf("別の経歴書を書けません: %v", err)
		}
		changed := r
		changed.Careers = slicesClone(r.Careers)
		changed.Careers[0].CompanyName = "書き換えてはいけない"
		changed.Projects = slicesClone(r.Projects)
		changed.Projects[0].Name = "書き換えてはいけない"
		changed.Projects[0].TechStack = TechStack{}
		if err := inTx(t.Context(), testPool, func(s store) error {
			results := []func() (bool, error){
				func() (bool, error) { return s.updateCareer(t.Context(), other.ID, changed.Careers[0]) },
				func() (bool, error) { return s.updateProject(t.Context(), other.ID, changed.Projects[0]) },
				func() (bool, error) { return s.updateCertification(t.Context(), other.ID, r.Certifications[0]) },
				func() (bool, error) { return s.updatePortfolio(t.Context(), other.ID, r.Portfolios[0]) },
				func() (bool, error) { return s.updateSnsPlatform(t.Context(), other.ID, r.SnsPlatforms[0]) },
				func() (bool, error) { return s.updateSelfPromotion(t.Context(), other.ID, r.SelfPromotions[0]) },
				func() (bool, error) { return s.deleteCareer(t.Context(), other.ID, r.Careers[0].ID) },
				func() (bool, error) { return s.deleteProject(t.Context(), other.ID, r.Projects[0].ID) },
				func() (bool, error) { return s.deleteCertification(t.Context(), other.ID, r.Certifications[0].ID) },
				func() (bool, error) { return s.deletePortfolio(t.Context(), other.ID, r.Portfolios[0].ID) },
				func() (bool, error) { return s.deleteSnsPlatform(t.Context(), other.ID, r.SnsPlatforms[0].ID) },
				func() (bool, error) { return s.deleteSelfPromotion(t.Context(), other.ID, r.SelfPromotions[0].ID) },
			}
			for i, f := range results {
				found, err := f()
				if err != nil {
					return err
				}
				if found {
					t.Errorf("%d 番目の操作が、別の経歴書の項目を見つけた", i)
				}
			}
			return nil
		}); err != nil {
			t.Fatalf("別の経歴書の項目を直せません: %v", err)
		}
		assertResume(t, mustFind(t, userID, r.ID), sorted(r))
		assertResume(t, mustFind(t, userID, other.ID), sorted(other))
	})

	t.Run("項目を足して消す", func(t *testing.T) {
		want := r
		added := Career{ID: uuid.New(), CompanyName: "株式会社D", Period: Period{StartDate: YearMonth{2010, time.April}, EndDate: yearMonth(2013, time.March)}}
		want.Careers = append(slicesClone(r.Careers[1:]), added)
		want.Projects = slicesClone(r.Projects[1:])
		want.Certifications = slicesClone(r.Certifications[1:])
		want.Portfolios = slicesClone(r.Portfolios[1:])
		want.SnsPlatforms = slicesClone(r.SnsPlatforms[1:])
		want.SelfPromotions = slicesClone(r.SelfPromotions[1:])
		want.UpdatedAt = japanTime(2026, time.December, 2, 9, 0, 0, 0)
		if err := inTx(t.Context(), testPool, func(s store) error {
			if err := s.insertCareer(t.Context(), r.ID, added); err != nil {
				return err
			}
			for _, del := range []func() (bool, error){
				func() (bool, error) { return s.deleteCareer(t.Context(), r.ID, r.Careers[0].ID) },
				func() (bool, error) { return s.deleteProject(t.Context(), r.ID, r.Projects[0].ID) },
				func() (bool, error) { return s.deleteCertification(t.Context(), r.ID, r.Certifications[0].ID) },
				func() (bool, error) { return s.deletePortfolio(t.Context(), r.ID, r.Portfolios[0].ID) },
				func() (bool, error) { return s.deleteSnsPlatform(t.Context(), r.ID, r.SnsPlatforms[0].ID) },
				func() (bool, error) { return s.deleteSelfPromotion(t.Context(), r.ID, r.SelfPromotions[0].ID) },
			} {
				found, err := del()
				if err != nil {
					return err
				}
				if !found {
					t.Error("消す項目が見つからない")
				}
			}
			return s.touchResume(t.Context(), r.ID, want.UpdatedAt)
		}); err != nil {
			t.Fatalf("項目を足して消せません: %v", err)
		}
		assertResume(t, mustFind(t, userID, r.ID), sorted(want))
		var techRows int
		if err := testPool.QueryRow(t.Context(), `SELECT count(*) FROM project_tech_stacks WHERE project_id = $1::uuid`,
			r.Projects[0].ID.String()).Scan(&techRows); err != nil {
			t.Fatalf("技術スタックの行を数えられません: %v", err)
		}
		if techRows != 0 {
			t.Errorf("消したプロジェクトの技術スタックの行が %d 行残っている", techRows)
		}
		r = want
	})

	t.Run("利用者の経歴書の一覧と数と名前の重なりを読む", func(t *testing.T) {
		// 作成の日時の順に並ぶ。fullResume の経歴書は、どれも同じ作成の日時なので、作成の日時の違う経歴書を足して確かめる。
		newer := fullResume(userID)
		newer.Name = "新しい経歴書"
		newer.CreatedAt = japanTime(2026, time.November, 20, 0, 0, 0, 0)
		older := fullResume(userID)
		older.Name = "古い経歴書"
		older.CreatedAt = japanTime(2026, time.November, 1, 0, 0, 0, 0)
		if err := inTx(t.Context(), testPool, func(s store) error {
			if err := s.insertResume(t.Context(), newer); err != nil {
				return err
			}
			return s.insertResume(t.Context(), older)
		}); err != nil {
			t.Fatalf("経歴書を書けません: %v", err)
		}
		list, err := testStore().listResumes(t.Context(), userID)
		if err != nil {
			t.Fatalf("経歴書の一覧を読めません: %v", err)
		}
		if len(list) != 4 || list[0].ID != older.ID || list[3].ID != newer.ID {
			t.Fatalf("経歴書の一覧の並び: %d 件 %v", len(list), list)
		}
		for _, l := range list {
			if len(l.Careers) != 0 || l.Name == "" || l.UserID != userID {
				t.Errorf("一覧の経歴書: %+v", l)
			}
		}
		if count, err := testStore().countResumes(t.Context(), userID); err != nil || count != 4 {
			t.Errorf("countResumes: %d %v", count, err)
		}
		if count, err := testStore().countResumes(t.Context(), insertTestUser(t)); err != nil || count != 0 {
			t.Errorf("経歴書の無い利用者の countResumes: %d %v", count, err)
		}
		for name, want := range map[string]bool{"新しい経歴書": true, "新しい経歴書 ": false, "無い経歴書": false} {
			if got, err := testStore().resumeNameExists(t.Context(), userID, name); err != nil || got != want {
				t.Errorf("resumeNameExists(%q): %v %v", name, got, err)
			}
		}
	})

	t.Run("経歴書を消すと子の表の行も消える", func(t *testing.T) {
		if err := inTx(t.Context(), testPool, func(s store) error { return s.deleteResume(t.Context(), r.ID) }); err != nil {
			t.Fatalf("経歴書を消せません: %v", err)
		}
		if _, found, err := testStore().findResume(t.Context(), userID, r.ID); err != nil || found {
			t.Errorf("消した経歴書の findResume: found=%v err=%v", found, err)
		}
		var rows int
		if err := testPool.QueryRow(t.Context(), `
			SELECT (SELECT count(*) FROM careers WHERE resume_id = $1::uuid)
			     + (SELECT count(*) FROM projects WHERE resume_id = $1::uuid)
			     + (SELECT count(*) FROM project_tech_stacks WHERE project_id = $2::uuid)
			     + (SELECT count(*) FROM certifications WHERE resume_id = $1::uuid)
			     + (SELECT count(*) FROM portfolios WHERE resume_id = $1::uuid)
			     + (SELECT count(*) FROM sns_platforms WHERE resume_id = $1::uuid)
			     + (SELECT count(*) FROM self_promotions WHERE resume_id = $1::uuid)`,
			r.ID.String(), r.Projects[0].ID.String()).Scan(&rows); err != nil {
			t.Fatalf("子の表の行を数えられません: %v", err)
		}
		if rows != 0 {
			t.Errorf("消した経歴書の子の表の行が %d 行残っている", rows)
		}
	})
}

// TestStore_RoundsToMicrosecond は、作成と更新の日時を、日本の時刻にし、マイクロ秒に四捨五入して書くことを確かめる(要件5の受入基準2)。
// pgjdbc がマイクロ秒に四捨五入して書くのと同じ値になる。
func TestStore_RoundsToMicrosecond(t *testing.T) {
	userID := insertTestUser(t)
	r := fullResume(userID)
	// 日本の時刻の 2026-11-14 10:23:45.1234565 を、時差の違う UTC の時刻で渡す。
	r.CreatedAt = time.Date(2026, time.November, 14, 1, 23, 45, 123456500, time.UTC)
	r.UpdatedAt = time.Date(2026, time.November, 14, 1, 23, 45, 123456499, time.UTC)
	if err := inTx(t.Context(), testPool, func(s store) error { return s.insertResume(t.Context(), r) }); err != nil {
		t.Fatalf("経歴書を書けません: %v", err)
	}
	check := func(t *testing.T, wantCreated, wantUpdated string) {
		t.Helper()
		var created, updated string
		if err := testPool.QueryRow(t.Context(), `SELECT created_at::text, updated_at::text FROM resumes WHERE id = $1::uuid`,
			r.ID.String()).Scan(&created, &updated); err != nil {
			t.Fatalf("経歴書の行を読めません: %v", err)
		}
		if created != wantCreated || updated != wantUpdated {
			t.Errorf("created_at=%s updated_at=%s, want %s %s", created, updated, wantCreated, wantUpdated)
		}
	}
	check(t, "2026-11-14 10:23:45.123457", "2026-11-14 10:23:45.123456")
	got := mustFind(t, userID, r.ID)
	if want := japanTime(2026, time.November, 14, 10, 23, 45, 123457000); !got.CreatedAt.Equal(want) {
		t.Errorf("読み直した作成の日時 %v, want %v", got.CreatedAt, want)
	}

	r.UpdatedAt = time.Date(2026, time.November, 15, 2, 0, 0, 999999500, time.UTC)
	if err := inTx(t.Context(), testPool, func(s store) error { return s.updateResumeBasic(t.Context(), r) }); err != nil {
		t.Fatalf("経歴書を直せません: %v", err)
	}
	check(t, "2026-11-14 10:23:45.123457", "2026-11-15 11:00:01")
	if err := inTx(t.Context(), testPool, func(s store) error {
		return s.touchResume(t.Context(), r.ID, time.Date(2026, time.November, 16, 3, 4, 5, 6000500, time.UTC))
	}); err != nil {
		t.Fatalf("更新の日時を書けません: %v", err)
	}
	check(t, "2026-11-14 10:23:45.123457", "2026-11-16 12:04:05.006001")
}

// TestStore_ProjectRollback は、プロジェクトの技術スタックの書き込みが失敗したとき、プロジェクトの行も残らないことを確かめる(要件5の受入基準1)。
// 技術スタックの名前に U+0000 を入れると、PostgreSQL の jsonb が断るので、技術スタックの書き込みだけが失敗する。
func TestStore_ProjectRollback(t *testing.T) {
	userID := insertTestUser(t)
	r := fullResume(userID)
	r.Projects = nil
	if err := inTx(t.Context(), testPool, func(s store) error { return s.insertResume(t.Context(), r) }); err != nil {
		t.Fatalf("経歴書を書けません: %v", err)
	}
	p := fullResume(userID).Projects[0]
	p.TechStack.Frontend.Languages = []*string{ptr("Go\x00")}
	if err := inTx(t.Context(), testPool, func(s store) error { return s.insertProject(t.Context(), r.ID, p) }); err == nil {
		t.Fatal("U+0000 を含む技術スタックの書き込みが失敗しない")
	}
	var rows int
	if err := testPool.QueryRow(t.Context(), `SELECT count(*) FROM projects WHERE id = $1::uuid`, p.ID.String()).Scan(&rows); err != nil {
		t.Fatalf("プロジェクトの行を数えられません: %v", err)
	}
	if rows != 0 {
		t.Errorf("技術スタックの書き込みが失敗したプロジェクトの行が %d 行残っている", rows)
	}

	// 直すときも、技術スタックの書き込みが失敗すれば、プロジェクトの行は直す前のままである。
	saved := fullResume(userID).Projects[1]
	if err := inTx(t.Context(), testPool, func(s store) error { return s.insertProject(t.Context(), r.ID, saved) }); err != nil {
		t.Fatalf("プロジェクトを書けません: %v", err)
	}
	broken := saved
	broken.Name = "書き換えてはいけない"
	broken.TechStack.Backend.Languages = []*string{ptr("\x00")}
	if err := inTx(t.Context(), testPool, func(s store) error {
		_, err := s.updateProject(t.Context(), r.ID, broken)
		return err
	}); err == nil {
		t.Fatal("U+0000 を含む技術スタックの書き直しが失敗しない")
	}
	got := mustFind(t, userID, r.ID)
	if len(got.Projects) != 1 || !reflect.DeepEqual(got.Projects[0], saved) {
		t.Errorf("書き直しが失敗したプロジェクト: %+v", got.Projects)
	}
}

// TestStore_NullCharacter は、U+0000 を含む文字列の書き込みを PostgreSQL が断り、行を書かないことを確かめる。
// Go の encoding/json は本文の \u0000 を U+0000 として読み、Java 版の Jackson も同じく読む。どちらの版も、PostgreSQL が断るので、
// 書き込みは失敗する。
func TestStore_NullCharacter(t *testing.T) {
	userID := insertTestUser(t)
	r := fullResume(userID)
	r.Name = "経歴書\x00"
	if err := inTx(t.Context(), testPool, func(s store) error { return s.insertResume(t.Context(), r) }); err == nil {
		t.Fatal("U+0000 を含む経歴書の名前の書き込みが失敗しない")
	}
	if _, found, err := testStore().findResume(t.Context(), userID, r.ID); err != nil || found {
		t.Errorf("書き込みが失敗した経歴書の findResume: found=%v err=%v", found, err)
	}
}

// TestStore_TechStackColumns は、技術スタックの35の小分類が、それぞれ Java 版と同じ project_tech_stacks の列に書かれることを確かめる(要件5の受入基準1)。
// 列の名前と小分類の組は、store.go の表とは別に、表の形(V1__create_tables.sql)と Java 版の対応から書く。小分類ごとに、その列の名前を
// 値にして書き、行を JSON で読んで、どの列にも自分の名前だけが入っていることを確かめる。
func TestStore_TechStackColumns(t *testing.T) {
	var tech TechStack
	columns := map[string]*[]*string{
		"frontend_languages":       &tech.Frontend.Languages,
		"frontend_framework":       &tech.Frontend.Frameworks,
		"frontend_libraries":       &tech.Frontend.Libraries,
		"frontend_build_tool":      &tech.Frontend.BuildTools,
		"frontend_package_manager": &tech.Frontend.PackageManagers,
		"frontend_linters":         &tech.Frontend.Linters,
		"frontend_formatters":      &tech.Frontend.Formatters,
		"frontend_testing_tools":   &tech.Frontend.TestingTools,
		"backend_languages":        &tech.Backend.Languages,
		"backend_framework":        &tech.Backend.Frameworks,
		"backend_libraries":        &tech.Backend.Libraries,
		"backend_build_tool":       &tech.Backend.BuildTools,
		"backend_package_manager":  &tech.Backend.PackageManagers,
		"backend_linters":          &tech.Backend.Linters,
		"backend_formatters":       &tech.Backend.Formatters,
		"backend_testing_tools":    &tech.Backend.TestingTools,
		"orm_tools":                &tech.Backend.OrmTools,
		"auth":                     &tech.Backend.Auth,
		"clouds":                   &tech.Infrastructure.Clouds,
		"operating_system":         &tech.Infrastructure.OperatingSystems,
		"containers":               &tech.Infrastructure.Containers,
		"database":                 &tech.Infrastructure.Databases,
		"web_server":               &tech.Infrastructure.WebServers,
		"ci_cd_tool":               &tech.Infrastructure.CiCdTools,
		"iac_tools":                &tech.Infrastructure.IacTools,
		"monitoring_tools":         &tech.Infrastructure.MonitoringTools,
		"logging_tools":            &tech.Infrastructure.LoggingTools,
		"source_control":           &tech.Tools.SourceControls,
		"project_management":       &tech.Tools.ProjectManagements,
		"communication_tool":       &tech.Tools.CommunicationTools,
		"documentation_tools":      &tech.Tools.DocumentationTools,
		"api_development_tools":    &tech.Tools.APIDevelopmentTools,
		"design_tools":             &tech.Tools.DesignTools,
		"editor":                   &tech.Tools.Editors,
		"development_environment":  &tech.Tools.DevelopmentEnvironments,
	}
	if len(columns) != 35 {
		t.Fatalf("列の数: got %d, want 35", len(columns))
	}
	for name, field := range columns {
		*field = []*string{ptr(name)}
	}

	userID := insertTestUser(t)
	r := fullResume(userID)
	r.Projects = r.Projects[:1]
	r.Projects[0].TechStack = tech
	if err := inTx(t.Context(), testPool, func(s store) error { return s.insertResume(t.Context(), r) }); err != nil {
		t.Fatalf("経歴書を書けません: %v", err)
	}

	var row []byte
	if err := testPool.QueryRow(t.Context(),
		`SELECT to_jsonb(p) - 'project_id' FROM project_tech_stacks p WHERE project_id = $1::uuid`,
		r.Projects[0].ID.String()).Scan(&row); err != nil {
		t.Fatalf("技術スタックの行を読めません: %v", err)
	}
	var got map[string][]string
	if err := json.Unmarshal(row, &got); err != nil {
		t.Fatalf("技術スタックの行を JSON で読めません: %v", err)
	}
	if len(got) != len(columns) {
		t.Errorf("表の列の数: got %d, want %d", len(got), len(columns))
	}
	for name := range columns {
		if v, ok := got[name]; !ok || !reflect.DeepEqual(v, []string{name}) {
			t.Errorf("列 %s の値: got %q(ある: %v), want [%s]", name, v, ok, name)
		}
	}

	assertResume(t, mustFind(t, userID, r.ID), sorted(r))
}

// TestStoreIntegration_UserExists は、利用者が居るかの問い合わせが、居る利用者に true を、
// 退会して行が消えた利用者と、もとから居ない ID に false を返すことを確かめる。
func TestStoreIntegration_UserExists(t *testing.T) {
	ctx := t.Context()
	s := testStore()

	present := insertTestUser(t)
	left := insertTestUser(t)
	if _, err := testPool.Exec(ctx, `DELETE FROM users WHERE id = $1::uuid`, left.String()); err != nil {
		t.Fatalf("退会した利用者の行を消せません: %v", err)
	}

	for _, c := range []struct {
		name   string
		userID uuid.UUID
		want   bool
	}{
		{"居る利用者", present, true},
		{"退会した利用者", left, false},
		{"もとから居ない ID", uuid.New(), false},
	} {
		t.Run(c.name, func(t *testing.T) {
			got, err := s.userExists(ctx, c.userID)
			if err != nil {
				t.Fatalf("利用者が居るかを調べられません: %v", err)
			}
			if got != c.want {
				t.Errorf("userExists(%s) = %v, want %v", c.userID, got, c.want)
			}
		})
	}
}
