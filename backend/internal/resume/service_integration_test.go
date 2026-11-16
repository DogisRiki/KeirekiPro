package resume

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// errRollback は、テストの中のトランザクションを取り消すために返す誤りである。
var errRollback = errors.New("テストのトランザクションを取り消す")

// inRollbackTx は、fn を、最後に取り消すトランザクションの中で呼ぶ。マスタの行を消した状態を、ほかのテストに見せずに作るためである。
func inRollbackTx(t *testing.T, fn func(tx pgx.Tx, s store)) {
	t.Helper()
	err := pgx.BeginFunc(t.Context(), testPool, func(tx pgx.Tx) error {
		fn(tx, store{q: sqlcgen.New(tx)})
		return errRollback
	})
	if !errors.Is(err, errRollback) {
		t.Fatalf("テストのトランザクションが失敗した: %v", err)
	}
}

// queryNames は、名前の1列を返す SQL を流し、名前の並びを返す。行が無ければ空の並びを返す。
func queryNames(t *testing.T, sql string, args ...any) []string {
	t.Helper()
	rows, err := testPool.Query(t.Context(), sql, args...)
	if err != nil {
		t.Fatalf("名前を読めません: %v", err)
	}
	names, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		t.Fatalf("名前を読めません: %v", err)
	}
	return append(make([]string, 0, len(names)), names...)
}

// TestService_MastersListNames は、資格と SNS のマスタの名前を、表に入っている並びのまま返すことを確かめる(要件1の受入基準2)。
// 並びが Java 版と同じことは、小タスク6.1 の masters.yaml で確かめる。
func TestService_MastersListNames(t *testing.T) {
	svc := New(Deps{Pool: testPool})
	for _, c := range []struct {
		name  string
		table string
		list  func() ([]string, error)
		store func(s store) ([]string, error)
	}{
		{
			"資格", "certification_mst",
			func() ([]string, error) { return svc.ListCertificationNames(t.Context()) },
			func(s store) ([]string, error) { return s.listCertificationNames(t.Context()) },
		},
		{
			"SNS", "sns_platform_mst",
			func() ([]string, error) { return svc.ListSnsPlatformNames(t.Context()) },
			func(s store) ([]string, error) { return s.listSnsPlatformNames(t.Context()) },
		},
	} {
		t.Run(c.name+"の名前を表の並びのまま返す", func(t *testing.T) {
			got, err := c.list()
			if err != nil {
				t.Fatalf("名前を読めません: %v", err)
			}
			want := queryNames(t, "SELECT name FROM "+c.table)
			if len(want) == 0 {
				t.Fatalf("%s に行が無い", c.table)
			}
			if !reflect.DeepEqual(got, want) {
				t.Errorf("名前の並びが違う\n got: %q\nwant: %q", got, want)
			}
		})
		t.Run(c.name+"のマスタが空なら空の並びを返す", func(t *testing.T) {
			inRollbackTx(t, func(tx pgx.Tx, s store) {
				if _, err := tx.Exec(t.Context(), "DELETE FROM "+c.table); err != nil {
					t.Fatalf("マスタの行を消せません: %v", err)
				}
				got, err := c.store(s)
				if err != nil {
					t.Fatalf("名前を読めません: %v", err)
				}
				if got == nil || len(got) != 0 {
					t.Errorf("空のマスタの名前: got %#v, want 空の並び", got)
				}
			})
		})
	}
}

// techStackKeys は、技術スタックのマスタの大分類と小分類の組と、答えの小分類の並びの組である。
// store の振り分けの表とは別に、Java 版の MyBatisTechStackListQuery の対応から書く。
func techStackKeys(m *TechStackMaster) map[[2]string]*[]string {
	return map[[2]string]*[]string{
		{"frontend", "languages"}:             &m.Frontend.Languages,
		{"frontend", "framework"}:             &m.Frontend.Frameworks,
		{"frontend", "libraries"}:             &m.Frontend.Libraries,
		{"frontend", "buildTool"}:             &m.Frontend.BuildTools,
		{"frontend", "packageManager"}:        &m.Frontend.PackageManagers,
		{"frontend", "linters"}:               &m.Frontend.Linters,
		{"frontend", "formatters"}:            &m.Frontend.Formatters,
		{"frontend", "testingTools"}:          &m.Frontend.TestingTools,
		{"backend", "languages"}:              &m.Backend.Languages,
		{"backend", "framework"}:              &m.Backend.Frameworks,
		{"backend", "libraries"}:              &m.Backend.Libraries,
		{"backend", "buildTool"}:              &m.Backend.BuildTools,
		{"backend", "packageManager"}:         &m.Backend.PackageManagers,
		{"backend", "linters"}:                &m.Backend.Linters,
		{"backend", "formatters"}:             &m.Backend.Formatters,
		{"backend", "testingTools"}:           &m.Backend.TestingTools,
		{"backend", "ormTools"}:               &m.Backend.OrmTools,
		{"backend", "auth"}:                   &m.Backend.Auth,
		{"infrastructure", "clouds"}:          &m.Infrastructure.Clouds,
		{"infrastructure", "operatingSystem"}: &m.Infrastructure.OperatingSystems,
		{"infrastructure", "containers"}:      &m.Infrastructure.Containers,
		{"infrastructure", "database"}:        &m.Infrastructure.Databases,
		{"infrastructure", "webServer"}:       &m.Infrastructure.WebServers,
		{"infrastructure", "ciCdTool"}:        &m.Infrastructure.CiCdTools,
		{"infrastructure", "iacTools"}:        &m.Infrastructure.IacTools,
		{"infrastructure", "monitoringTools"}: &m.Infrastructure.MonitoringTools,
		{"infrastructure", "loggingTools"}:    &m.Infrastructure.LoggingTools,
		{"tools", "sourceControl"}:            &m.Tools.SourceControls,
		{"tools", "projectManagement"}:        &m.Tools.ProjectManagements,
		{"tools", "communicationTool"}:        &m.Tools.CommunicationTools,
		{"tools", "documentationTools"}:       &m.Tools.DocumentationTools,
		{"tools", "apiDevelopmentTools"}:      &m.Tools.APIDevelopmentTools,
		{"tools", "designTools"}:              &m.Tools.DesignTools,
		{"tools", "editor"}:                   &m.Tools.Editors,
		{"tools", "developmentEnvironment"}:   &m.Tools.DevelopmentEnvironments,
	}
}

// TestService_MastersTechStacks は、技術スタックのマスタの名前を、大分類と小分類の組ごとに答えの小分類に振り分け、
// 対応の無い小分類と大分類の行を捨てることを確かめる(要件1の受入基準2)。
// 35の組のそれぞれと、対応の無い2つの組に、テストの名前を1つずつ足してから読む。足した行は、テストの終わりに消す。
func TestService_MastersTechStacks(t *testing.T) {
	keys := techStackKeys(&TechStackMaster{})
	if len(keys) != 35 {
		t.Fatalf("小分類の組の数: got %d, want 35", len(keys))
	}
	type extra struct{ main, sub, name string }
	extras := []extra{
		{"frontend", "unknownSub", "テスト:対応の無い小分類"},
		{"unknownMain", "languages", "テスト:対応の無い大分類"},
	}
	for k := range keys {
		extras = append(extras, extra{k[0], k[1], "テスト:" + k[0] + "/" + k[1]})
	}
	t.Cleanup(func() {
		ctx := context.Background()
		for _, sql := range []string{
			`DELETE FROM tech_stack_mst WHERE id >= 900000`,
			`DELETE FROM tech_stack_category_mst WHERE code LIKE 'test:%'`,
		} {
			if _, err := testPool.Exec(ctx, sql); err != nil {
				t.Errorf("テストで足したマスタの行を消せません: %v", err)
			}
		}
	})
	for i, e := range extras {
		code := "test:" + e.main + "/" + e.sub
		if _, err := testPool.Exec(t.Context(),
			`INSERT INTO tech_stack_category_mst (code, main_category, sub_category) VALUES ($1, $2, $3)`,
			code, e.main, e.sub); err != nil {
			t.Fatalf("小分類の行を足せません: %v", err)
		}
		if _, err := testPool.Exec(t.Context(),
			`INSERT INTO tech_stack_mst (id, name, category_code) VALUES ($1, $2, $3)`,
			900000+i, e.name, code); err != nil {
			t.Fatalf("技術スタックの行を足せません: %v", err)
		}
	}

	got, err := New(Deps{Pool: testPool}).ListTechStacks(t.Context())
	if err != nil {
		t.Fatalf("技術スタックのマスタを読めません: %v", err)
	}
	total := 0
	for k, field := range techStackKeys(&got) {
		want := queryNames(t, `SELECT m.name FROM tech_stack_category_mst c JOIN tech_stack_mst m ON m.category_code = c.code
			WHERE c.main_category = $1 AND c.sub_category = $2 ORDER BY m.id`, k[0], k[1])
		if !reflect.DeepEqual(*field, want) {
			t.Errorf("%s/%s の名前が違う\n got: %q\nwant: %q", k[0], k[1], *field, want)
		}
		if n := len(*field); n == 0 || (*field)[n-1] != "テスト:"+k[0]+"/"+k[1] {
			t.Errorf("%s/%s の最後に、足したテストの名前が無い: %q", k[0], k[1], *field)
		}
		total += len(*field)
	}
	all := len(queryNames(t, `SELECT name FROM tech_stack_mst`))
	if total != all-2 {
		t.Errorf("振り分けた名前の数: got %d, want %d(対応の無い2つの行を除くすべての行)", total, all-2)
	}

	t.Run("マスタが空なら35の小分類のすべてを空の並びで返す", func(t *testing.T) {
		inRollbackTx(t, func(tx pgx.Tx, s store) {
			if _, err := tx.Exec(t.Context(), `DELETE FROM tech_stack_mst`); err != nil {
				t.Fatalf("マスタの行を消せません: %v", err)
			}
			empty, err := s.listTechStacks(t.Context())
			if err != nil {
				t.Fatalf("技術スタックのマスタを読めません: %v", err)
			}
			for k, field := range techStackKeys(&empty) {
				if *field == nil || len(*field) != 0 {
					t.Errorf("%s/%s: got %#v, want 空の並び", k[0], k[1], *field)
				}
			}
		})
	})
}

// saveResume は、経歴書と6つの欄の項目をデータベースに書く。
func saveResume(t *testing.T, r Resume) {
	t.Helper()
	if err := inTx(t.Context(), testPool, func(s store) error { return s.insertResume(t.Context(), r) }); err != nil {
		t.Fatalf("経歴書を書けません: %v", err)
	}
}

// countRows は、経歴書の行と、6つの欄の項目の行と、プロジェクトの技術スタックの行を合わせた数を返す。
func countRows(t *testing.T, r Resume) int {
	t.Helper()
	projectIDs := make([]string, 0, len(r.Projects))
	for _, p := range r.Projects {
		projectIDs = append(projectIDs, p.ID.String())
	}
	var n int
	if err := testPool.QueryRow(t.Context(), `
		SELECT (SELECT count(*) FROM resumes WHERE id = $1::uuid)
		     + (SELECT count(*) FROM careers WHERE resume_id = $1::uuid)
		     + (SELECT count(*) FROM projects WHERE resume_id = $1::uuid)
		     + (SELECT count(*) FROM project_tech_stacks WHERE project_id = ANY($2::uuid[]))
		     + (SELECT count(*) FROM certifications WHERE resume_id = $1::uuid)
		     + (SELECT count(*) FROM portfolios WHERE resume_id = $1::uuid)
		     + (SELECT count(*) FROM sns_platforms WHERE resume_id = $1::uuid)
		     + (SELECT count(*) FROM self_promotions WHERE resume_id = $1::uuid)`,
		r.ID.String(), projectIDs).Scan(&n); err != nil {
		t.Fatalf("経歴書の行を数えられません: %v", err)
	}
	return n
}

// fullRows は、fullResume の経歴書をデータベースに書いたときの行の数である。経歴書の1行、6つの欄の2行ずつ、技術スタックの2行である。
const fullRows = 1 + 6*2 + 2

// assertResumeNotFound は、誤りが、無い経歴書の 404 の誤りであることを確かめる。
func assertResumeNotFound(t *testing.T, err error) {
	t.Helper()
	if !reflect.DeepEqual(err, error(errResumeNotFound())) {
		t.Errorf("誤り: got %#v, want 無い経歴書の誤り %#v", err, errResumeNotFound())
	}
}

// unreadableIDs は、parseID が読めない経路の経歴書の ID である。
var unreadableIDs = []string{"", "abc", "00000000-0000-0000-0000-00000000000g", "00000000-0000-0000-0000-0000000000001"}

// TestService_ListResumes は、利用者の経歴書だけを作成の日時の順に返し、項目を読まないことを確かめる。
func TestService_ListResumes(t *testing.T) {
	userID := insertTestUser(t)
	svc := New(Deps{Pool: testPool})

	got, err := svc.ListResumes(t.Context(), userID)
	if err != nil {
		t.Fatalf("経歴書の一覧を読めません: %v", err)
	}
	if got == nil || len(got) != 0 {
		t.Errorf("経歴書の無い利用者の一覧: got %#v, want 空の並び", got)
	}

	newer := fullResume(userID)
	newer.Name = "新しい経歴書"
	newer.CreatedAt = japanTime(2026, time.March, 2, 9, 0, 0, 0)
	newer.UpdatedAt = japanTime(2026, time.March, 3, 9, 0, 0, 0)
	older := fullResume(userID)
	older.Name = "古い経歴書"
	older.CreatedAt = japanTime(2026, time.March, 1, 9, 0, 0, 0)
	older.UpdatedAt = japanTime(2026, time.March, 4, 9, 0, 0, 0)
	other := fullResume(insertTestUser(t))
	for _, r := range []Resume{newer, other, older} {
		saveResume(t, r)
	}

	got, err = svc.ListResumes(t.Context(), userID)
	if err != nil {
		t.Fatalf("経歴書の一覧を読めません: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("経歴書の数: got %d, want 2: %+v", len(got), got)
	}
	for i, want := range []Resume{older, newer} {
		g := got[i]
		if g.ID != want.ID || g.UserID != userID || g.Name != want.Name ||
			!g.CreatedAt.Equal(want.CreatedAt) || !g.UpdatedAt.Equal(want.UpdatedAt) {
			t.Errorf("%d 番目の経歴書: got %+v, want ID=%s 名前=%s 作成=%v 更新=%v",
				i, g, want.ID, want.Name, want.CreatedAt, want.UpdatedAt)
		}
		if len(g.Careers)+len(g.Projects)+len(g.Certifications)+len(g.Portfolios)+len(g.SnsPlatforms)+len(g.SelfPromotions) != 0 {
			t.Errorf("%d 番目の経歴書が項目を持つ: %+v", i, g)
		}
	}
}

// TestService_ListResumesDeletedUser は、退会してすでに居ない利用者の経歴書の一覧が、誤りでなく空の並びになることを確かめる(要件3の受入基準4)。
func TestService_ListResumesDeletedUser(t *testing.T) {
	got, err := New(Deps{Pool: testPool}).ListResumes(t.Context(), uuid.New())
	if err != nil {
		t.Fatalf("居ない利用者の経歴書の一覧: %v", err)
	}
	if got == nil || len(got) != 0 {
		t.Errorf("居ない利用者の経歴書の一覧: got %#v, want 空の並び", got)
	}
}

// TestService_GetResume は、利用者の経歴書1件を6つの欄の項目と一緒に Java 版と同じ順で返し、
// 無い経歴書と読めない ID に無い経歴書の誤りを返すことを確かめる。
func TestService_GetResume(t *testing.T) {
	userID := insertTestUser(t)
	r := fullResume(userID)
	saveResume(t, r)
	svc := New(Deps{Pool: testPool})

	for _, id := range []string{r.ID.String(), strings.ToUpper(r.ID.String())} {
		got, err := svc.GetResume(t.Context(), userID, id)
		if err != nil {
			t.Fatalf("経歴書 %s を読めません: %v", id, err)
		}
		assertResume(t, got, sorted(r))
	}
	for _, id := range append([]string{uuid.NewString()}, unreadableIDs...) {
		_, err := svc.GetResume(t.Context(), userID, id)
		assertResumeNotFound(t, err)
	}
}

// TestService_GetResumeOtherUser は、ほかの利用者の経歴書を返さず、無い経歴書と同じ誤りを返し、経歴書の行が残ることを確かめる(要件3の受入基準1)。
func TestService_GetResumeOtherUser(t *testing.T) {
	owner := insertTestUser(t)
	r := fullResume(owner)
	saveResume(t, r)

	_, err := New(Deps{Pool: testPool}).GetResume(t.Context(), insertTestUser(t), r.ID.String())
	assertResumeNotFound(t, err)
	if n := countRows(t, r); n != fullRows {
		t.Errorf("経歴書の行の数: got %d, want %d", n, fullRows)
	}
}

// TestService_DeleteResume は、利用者の経歴書を6つの欄の項目と技術スタックの行と一緒に消し、
// 無い経歴書と読めない ID に無い経歴書の誤りを返すことを確かめる。
func TestService_DeleteResume(t *testing.T) {
	userID := insertTestUser(t)
	r := fullResume(userID)
	kept := fullResume(userID)
	kept.Name = "残す経歴書"
	saveResume(t, r)
	saveResume(t, kept)
	svc := New(Deps{Pool: testPool})

	for _, id := range append([]string{uuid.NewString()}, unreadableIDs...) {
		assertResumeNotFound(t, svc.DeleteResume(t.Context(), userID, id))
	}
	if err := svc.DeleteResume(t.Context(), userID, r.ID.String()); err != nil {
		t.Fatalf("経歴書を消せません: %v", err)
	}
	if n := countRows(t, r); n != 0 {
		t.Errorf("消した経歴書の行が %d 行残っている", n)
	}
	if n := countRows(t, kept); n != fullRows {
		t.Errorf("消していない経歴書の行の数: got %d, want %d", n, fullRows)
	}
	assertResumeNotFound(t, svc.DeleteResume(t.Context(), userID, r.ID.String()))
}

// TestService_DeleteResumeOtherUser は、ほかの利用者の経歴書を消さず、無い経歴書と同じ誤りを返すことを確かめる(要件3の受入基準1)。
func TestService_DeleteResumeOtherUser(t *testing.T) {
	owner := insertTestUser(t)
	r := fullResume(owner)
	saveResume(t, r)

	assertResumeNotFound(t, New(Deps{Pool: testPool}).DeleteResume(t.Context(), insertTestUser(t), r.ID.String()))
	if n := countRows(t, r); n != fullRows {
		t.Errorf("経歴書の行の数: got %d, want %d", n, fullRows)
	}
	assertResume(t, mustFind(t, owner, r.ID), sorted(r))
}
