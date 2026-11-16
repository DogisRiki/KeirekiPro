package resume

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
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

// fixedNow は、いつも t を返す時刻の関数である。
func fixedNow(t time.Time) func() time.Time {
	return func() time.Time { return t }
}

// jsonBody は、要求の本文を JSON に書く。
func jsonBody(t *testing.T, v map[string]any) []byte {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("本文を書けません: %v", err)
	}
	return b
}

// assertError は、誤りが want と同じ状態の番号と文言と項目ごとの文言を持つことを確かめる。
func assertError(t *testing.T, name string, got error, want *auth.Error) {
	t.Helper()
	if !reflect.DeepEqual(got, error(want)) {
		t.Errorf("%s: 誤り: got %#v, want %#v", name, got, want)
	}
}

// fieldError は、1つの項目に1つの文言を持つ入力の誤りである。
func fieldError(field, message string) *auth.Error {
	return auth.ErrInvalidInput(map[string][]string{field: {message}})
}

// countUserResumes は、利用者の経歴書の行の数を返す。
func countUserResumes(t *testing.T, userID uuid.UUID) int {
	t.Helper()
	var n int
	if err := testPool.QueryRow(t.Context(), `SELECT count(*) FROM resumes WHERE user_id = $1::uuid`, userID.String()).Scan(&n); err != nil {
		t.Fatalf("経歴書の行を数えられません: %v", err)
	}
	return n
}

// storedTimes は、データベースに書いた経歴書の作成と更新の日時と日付を、表の値の見た目の文字列で返す。
func storedTimes(t *testing.T, resumeID uuid.UUID) (created, updated, date string) {
	t.Helper()
	if err := testPool.QueryRow(t.Context(), `
		SELECT to_char(created_at, 'YYYY-MM-DD HH24:MI:SS.US'), to_char(updated_at, 'YYYY-MM-DD HH24:MI:SS.US'), to_char(date, 'YYYY-MM-DD')
		FROM resumes WHERE id = $1::uuid`, resumeID.String()).Scan(&created, &updated, &date); err != nil {
		t.Fatalf("経歴書の日時を読めません: %v", err)
	}
	return created, updated, date
}

// emptyResume は、6つの欄の項目を持たない経歴書を作る。
func emptyResume(userID uuid.UUID, name string) Resume {
	return Resume{
		ID: uuid.New(), UserID: userID, Name: name, Date: Date{Year: 2026, Month: time.November, Day: 1},
		CreatedAt: japanTime(2026, time.November, 1, 9, 0, 0, 0), UpdatedAt: japanTime(2026, time.November, 1, 9, 0, 0, 0),
	}
}

// TestService_CreateResume は、写さない作成が、名前と日本の今日の日付と空の項目の経歴書を作ることと、本文と入力欄と名前の決まりの
// 誤りを返して何も書かないことを確かめる。
func TestService_CreateResume(t *testing.T) {
	userID := insertTestUser(t)
	now := japanTime(2026, time.November, 14, 10, 23, 45, 0)
	svc := New(Deps{Pool: testPool, Now: fixedNow(now)})

	for _, c := range []struct {
		name string
		body []byte
		want *auth.Error
	}{
		{"読めない本文", []byte(`{`), errUnreadableInput()},
		{"本文が並び", []byte(`[]`), errUnreadableInput()},
		{"読めない resumeId", []byte(`{"resumeName":"経歴書","resumeId":"abc"}`), errUnreadableInput()},
		{"名前が無い", []byte(`{}`), fieldError("resumeName", MessageResumeNameRequired)},
		{"使えない文字", jsonBody(t, map[string]any{"resumeName": "経歴書/1"}), fieldError("resumeName", MessageResumeNameInvalidChars)},
		{"先頭の点", jsonBody(t, map[string]any{"resumeName": ".経歴書"}), fieldError("resumeName", MessageResumeNameDotEdge)},
	} {
		_, err := svc.CreateResume(t.Context(), userID, c.body)
		assertError(t, c.name, err, c.want)
	}
	if n := countUserResumes(t, userID); n != 0 {
		t.Fatalf("誤りの要求で経歴書が %d 件書かれた", n)
	}

	for _, b := range [][]byte{
		jsonBody(t, map[string]any{"resumeName": "経歴書"}),
		jsonBody(t, map[string]any{"resumeName": "経歴書2", "resumeId": ""}),
		jsonBody(t, map[string]any{"resumeName": "経歴書3", "resumeId": nil}),
	} {
		got, err := svc.CreateResume(t.Context(), userID, b)
		if err != nil {
			t.Fatalf("経歴書を作れません(%s): %v", b, err)
		}
		if got.ID == uuid.Nil || got.UserID != userID || got.Date != (Date{Year: 2026, Month: time.November, Day: 14}) ||
			got.LastName != nil || got.FirstName != nil {
			t.Errorf("作った経歴書(%s): %+v", b, got)
		}
		assertResume(t, mustFind(t, userID, got.ID), got)
	}
	if n := countUserResumes(t, userID); n != 3 {
		t.Errorf("経歴書の数: got %d, want 3", n)
	}
}

// TestService_CreateResumeLimitBeforeDuplicate は、経歴書の作成が、Java 版と同じく、上限、名前の重なり、名前の決まりの順に確かめることを確かめる(要件2の受入基準1)。
func TestService_CreateResumeLimitBeforeDuplicate(t *testing.T) {
	userID := insertTestUser(t)
	other := insertTestUser(t)
	saveResume(t, emptyResume(other, "他人の経歴書"))
	for i := range 49 {
		saveResume(t, emptyResume(userID, fmt.Sprintf("経歴書%d", i)))
	}
	svc := New(Deps{Pool: testPool, Now: fixedNow(japanTime(2026, time.November, 14, 10, 0, 0, 0))})
	create := func(name string) error {
		_, err := svc.CreateResume(t.Context(), userID, jsonBody(t, map[string]any{"resumeName": name}))
		return err
	}

	assertError(t, "49件で重なる名前", create("経歴書0"), errResumeNameDuplicated())
	assertError(t, "49件で使えない文字", create("経歴書/0"), fieldError("resumeName", MessageResumeNameInvalidChars))
	if err := create("他人の経歴書"); err != nil {
		t.Fatalf("ほかの利用者の経歴書と同じ名前で作れません: %v", err)
	}

	limit := errLimitReached(MessageResumeLimitFormat, 50, 50)
	assertError(t, "50件で重なる名前", create("経歴書0"), limit)
	assertError(t, "50件で使えない文字", create("経歴書/0"), limit)
	assertError(t, "50件で新しい名前", create("新しい経歴書"), limit)
	if n := countUserResumes(t, userID); n != 50 {
		t.Errorf("経歴書の数: got %d, want 50", n)
	}
}

// TestService_CreateResumeCopy は、写して作る経歴書が、6つの欄の項目に新しい ID を付け、日付と姓と名をコピー元の値にし、
// 項目を Java 版と同じ順に並べることを確かめる。コピー元が無いときは、名前の決まりより先に無い経歴書の誤りを返すことも確かめる。
func TestService_CreateResumeCopy(t *testing.T) {
	userID := insertTestUser(t)
	src := fullResume(userID)
	src.FirstName = ptr("太郎")
	saveResume(t, src)
	now := japanTime(2026, time.December, 1, 8, 0, 0, 0)
	svc := New(Deps{Pool: testPool, Now: fixedNow(now)})

	for _, name := range []string{"写し", "写し/1"} {
		_, err := svc.CreateResume(t.Context(), userID, jsonBody(t, map[string]any{"resumeName": name, "resumeId": uuid.NewString()}))
		assertError(t, "無いコピー元("+name+")", err, errResumeNotFound())
	}
	_, err := svc.CreateResume(t.Context(), userID, jsonBody(t, map[string]any{"resumeName": "写し/1", "resumeId": src.ID.String()}))
	assertError(t, "使えない文字", err, fieldError("resumeName", MessageResumeNameInvalidChars))

	got, err := svc.CreateResume(t.Context(), userID, jsonBody(t, map[string]any{"resumeName": "写し", "resumeId": strings.ToUpper(src.ID.String())}))
	if err != nil {
		t.Fatalf("経歴書を写して作れません: %v", err)
	}
	if got.ID == src.ID || got.Name != "写し" || got.UserID != userID || got.Date != src.Date ||
		!reflect.DeepEqual(got.LastName, src.LastName) || !reflect.DeepEqual(got.FirstName, src.FirstName) ||
		!got.CreatedAt.Equal(now) || !got.UpdatedAt.Equal(now) {
		t.Errorf("写した経歴書: %+v", got)
	}

	srcIDs := map[uuid.UUID]bool{src.ID: true}
	for _, id := range entryIDs(src) {
		srcIDs[id] = true
	}
	gotIDs := entryIDs(got)
	if len(gotIDs) != len(entryIDs(src)) {
		t.Fatalf("写した項目の数: got %d, want %d", len(gotIDs), len(entryIDs(src)))
	}
	seen := map[uuid.UUID]bool{}
	for _, id := range gotIDs {
		if srcIDs[id] || seen[id] || id == uuid.Nil {
			t.Errorf("写した項目の ID %s が新しくない", id)
		}
		seen[id] = true
	}

	stored := mustFind(t, userID, got.ID)
	assertResume(t, stored, got)
	want := sorted(src)
	stripIDs(&want)
	stripIDs(&stored)
	want.ID, want.Name, want.CreatedAt, want.UpdatedAt = stored.ID, "写し", stored.CreatedAt, stored.UpdatedAt
	if !reflect.DeepEqual(stored, want) {
		t.Errorf("写した経歴書の中身がコピー元と違う\n got: %+v\nwant: %+v", stored, want)
	}
	assertResume(t, mustFind(t, userID, src.ID), sorted(src))
}

// entryIDs は、経歴書の6つの欄の項目の ID を並べる。
func entryIDs(r Resume) []uuid.UUID {
	var ids []uuid.UUID
	for _, c := range r.Careers {
		ids = append(ids, c.ID)
	}
	for _, p := range r.Projects {
		ids = append(ids, p.ID)
	}
	for _, c := range r.Certifications {
		ids = append(ids, c.ID)
	}
	for _, p := range r.Portfolios {
		ids = append(ids, p.ID)
	}
	for _, p := range r.SnsPlatforms {
		ids = append(ids, p.ID)
	}
	for _, p := range r.SelfPromotions {
		ids = append(ids, p.ID)
	}
	return ids
}

// stripIDs は、経歴書の6つの欄の項目の ID を消し、項目を ID によらない順に並べ直す。
// ID が同じ順の決め手になる項目どうしも、中身で比べられるようにするためである。
func stripIDs(r *Resume) {
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
	sortEntries(r)
}

// TestService_CreateResumeCopyOtherUser は、ほかの利用者の経歴書を写せず、無い経歴書と同じ誤りを返し、何も書かないことを確かめる(要件3の受入基準1)。
func TestService_CreateResumeCopyOtherUser(t *testing.T) {
	owner := insertTestUser(t)
	src := fullResume(owner)
	saveResume(t, src)
	userID := insertTestUser(t)

	_, err := New(Deps{Pool: testPool}).CreateResume(t.Context(), userID,
		jsonBody(t, map[string]any{"resumeName": "写し", "resumeId": src.ID.String()}))
	assertResumeNotFound(t, err)
	if n := countUserResumes(t, userID); n != 0 {
		t.Errorf("ほかの利用者の経歴書を写した経歴書が %d 件ある", n)
	}
	if n := countRows(t, src); n != fullRows {
		t.Errorf("コピー元の行の数: got %d, want %d", n, fullRows)
	}
}

// TestService_CreateResumeDeletedUser は、退会してすでに居ない利用者の経歴書の作成が、無い経歴書と同じ誤りを返し、行を残さないことを確かめる(要件3の受入基準4)。
func TestService_CreateResumeDeletedUser(t *testing.T) {
	userID := uuid.New()
	svc := New(Deps{Pool: testPool})
	for _, b := range [][]byte{
		jsonBody(t, map[string]any{"resumeName": "経歴書"}),
		jsonBody(t, map[string]any{"resumeName": "経歴書", "resumeId": uuid.NewString()}),
	} {
		_, err := svc.CreateResume(t.Context(), userID, b)
		assertResumeNotFound(t, err)
	}
	if n := countUserResumes(t, userID); n != 0 {
		t.Errorf("居ない利用者の経歴書が %d 件書かれた", n)
	}
}

// TestService_CreateResumeJapanTime は、日本の時間帯でない時刻を返す Now を渡しても、作成と更新の日時を日本の時刻で書き、
// 経歴書の日付を日本の日付で書くことを確かめる(要件5の受入基準2)。
func TestService_CreateResumeJapanTime(t *testing.T) {
	userID := insertTestUser(t)
	now := time.Date(2026, time.November, 14, 15, 30, 0, 0, time.UTC)
	got, err := New(Deps{Pool: testPool, Now: fixedNow(now)}).CreateResume(t.Context(), userID,
		jsonBody(t, map[string]any{"resumeName": "経歴書"}))
	if err != nil {
		t.Fatalf("経歴書を作れません: %v", err)
	}
	if got.Date != (Date{Year: 2026, Month: time.November, Day: 15}) || got.CreatedAt.Location() != japanZone || got.UpdatedAt.Location() != japanZone {
		t.Errorf("作った経歴書の日付と日時: %+v", got)
	}
	created, updated, date := storedTimes(t, got.ID)
	if created != "2026-11-15 00:30:00.000000" || updated != created || date != "2026-11-15" {
		t.Errorf("表の値: 作成=%s 更新=%s 日付=%s, want 2026-11-15 00:30:00.000000 と 2026-11-15", created, updated, date)
	}
}

// TestService_CreateResumeReturnsUnroundedTime は、作成の答えの作成と更新の日時が、Java 版と同じく丸める前の値であり、
// データベースにはマイクロ秒に丸めた値を書くことを確かめる(要件1の受入基準1)。
func TestService_CreateResumeReturnsUnroundedTime(t *testing.T) {
	userID := insertTestUser(t)
	now := japanTime(2026, time.November, 14, 10, 23, 45, 123456500)
	src := emptyResume(userID, "コピー元")
	saveResume(t, src)
	svc := New(Deps{Pool: testPool, Now: fixedNow(now)})

	for _, b := range [][]byte{
		jsonBody(t, map[string]any{"resumeName": "経歴書"}),
		jsonBody(t, map[string]any{"resumeName": "写し", "resumeId": src.ID.String()}),
	} {
		got, err := svc.CreateResume(t.Context(), userID, b)
		if err != nil {
			t.Fatalf("経歴書を作れません(%s): %v", b, err)
		}
		if !got.CreatedAt.Equal(now) || !got.UpdatedAt.Equal(now) {
			t.Errorf("答えの日時(%s): 作成=%v 更新=%v, want %v", b, got.CreatedAt, got.UpdatedAt, now)
		}
		created, updated, _ := storedTimes(t, got.ID)
		if created != "2026-11-14 10:23:45.123457" || updated != created {
			t.Errorf("表の日時(%s): 作成=%s 更新=%s, want 2026-11-14 10:23:45.123457", b, created, updated)
		}
	}
}

// basicBody は、基本の情報の更新の要求の本文を作る。
func basicBody(t *testing.T, name, date, lastName, firstName string) []byte {
	return jsonBody(t, map[string]any{"resumeName": name, "date": date, "lastName": lastName, "firstName": firstName})
}

// TestService_UpdateResumeBasic は、基本の情報の更新が、名前と日付と姓と名を書き換え、項目を持つ経歴書を返すことと、
// Java 版と同じ順に誤りを返して何も書かないことを確かめる。
func TestService_UpdateResumeBasic(t *testing.T) {
	userID := insertTestUser(t)
	r := fullResume(userID)
	saveResume(t, r)
	saveResume(t, emptyResume(userID, "別の経歴書"))
	saveResume(t, emptyResume(insertTestUser(t), "他人の経歴書"))
	svc := New(Deps{Pool: testPool, Now: fixedNow(japanTime(2026, time.December, 2, 9, 0, 0, 0))})
	id := r.ID.String()

	for _, c := range []struct {
		name     string
		resumeID string
		body     []byte
		want     *auth.Error
	}{
		{"読めない本文", id, []byte(`{`), errUnreadableInput()},
		{"読めない本文と読めない ID", "abc", []byte(`{`), errUnreadableInput()},
		{"入力欄の誤りと無い経歴書", uuid.NewString(), []byte(`{}`), auth.ErrInvalidInput(map[string][]string{
			"resumeName": {MessageResumeNameRequired}, "date": {MessageDateRequired},
			"lastName": {MessageLastNameRequired}, "firstName": {MessageFirstNameRequired},
		})},
		{
			"入力欄の誤りと読めない ID", "abc", jsonBody(t, map[string]any{"resumeName": "経歴書", "date": "2026-12-01", "lastName": "山田"}),
			fieldError("firstName", MessageFirstNameRequired),
		},
		{"読めない ID", "abc", basicBody(t, "経歴書", "2026-12-01", "山田", "花子"), errResumeNotFound()},
		{"無い経歴書", uuid.NewString(), basicBody(t, "経歴書", "2026-12-01", "山田", "花子"), errResumeNotFound()},
		{"重なる名前と使えない姓", id, basicBody(t, "別の経歴書", "2026-12-01", "山田1", "花子"), errResumeNameDuplicated()},
		{"名前と姓と名の決まり", id, basicBody(t, "経歴書.", "2026-12-01", "山田1", "花子2"), auth.ErrInvalidInput(map[string][]string{
			"resumeName": {MessageResumeNameDotEdge},
			"lastName":   {MessageLastNameInvalidChars}, "firstName": {MessageFirstNameInvalidChars},
		})},
	} {
		_, err := svc.UpdateResumeBasic(t.Context(), userID, c.resumeID, c.body)
		assertError(t, c.name, err, c.want)
	}
	assertResume(t, mustFind(t, userID, r.ID), sorted(r))

	for _, name := range []string{r.Name, "他人の経歴書"} {
		got, err := svc.UpdateResumeBasic(t.Context(), userID, strings.ToUpper(id), basicBody(t, name, "2026-12-01", "山田", "花子"))
		if err != nil {
			t.Fatalf("基本の情報を %q に更新できません: %v", name, err)
		}
		want := sorted(r)
		want.Name, want.Date, want.LastName, want.FirstName = name, Date{Year: 2026, Month: time.December, Day: 1}, ptr("山田"), ptr("花子")
		want.UpdatedAt = japanTime(2026, time.December, 2, 9, 0, 0, 0)
		assertResume(t, got, want)
		assertResume(t, mustFind(t, userID, r.ID), want)
	}
}

// TestService_UpdateResumeBasicOtherUser は、ほかの利用者の経歴書の基本の情報を書き換えず、無い経歴書と同じ誤りを返すことを確かめる(要件3の受入基準1)。
func TestService_UpdateResumeBasicOtherUser(t *testing.T) {
	owner := insertTestUser(t)
	r := fullResume(owner)
	saveResume(t, r)

	_, err := New(Deps{Pool: testPool}).UpdateResumeBasic(t.Context(), insertTestUser(t), r.ID.String(),
		basicBody(t, "書き換え", "2026-12-01", "山田", "花子"))
	assertResumeNotFound(t, err)
	assertResume(t, mustFind(t, owner, r.ID), sorted(r))
}

// TestService_UpdateResumeBasicReturnsUnroundedUpdatedAt は、基本の情報の更新の答えの更新の日時が、Java 版と同じく丸める前の値であり、
// 作成の日時がデータベースの値であることを確かめる(要件1の受入基準1)。
func TestService_UpdateResumeBasicReturnsUnroundedUpdatedAt(t *testing.T) {
	userID := insertTestUser(t)
	r := emptyResume(userID, "経歴書")
	r.CreatedAt = japanTime(2026, time.November, 1, 9, 0, 0, 654321000)
	saveResume(t, r)
	now := japanTime(2026, time.November, 14, 10, 23, 45, 123456500)

	got, err := New(Deps{Pool: testPool, Now: fixedNow(now)}).UpdateResumeBasic(t.Context(), userID, r.ID.String(),
		basicBody(t, "経歴書", "2026-12-01", "山田", "花子"))
	if err != nil {
		t.Fatalf("基本の情報を更新できません: %v", err)
	}
	if !got.UpdatedAt.Equal(now) || got.UpdatedAt.Location() != japanZone {
		t.Errorf("答えの更新の日時: got %v, want %v", got.UpdatedAt, now)
	}
	if stored := mustFind(t, userID, r.ID); !got.CreatedAt.Equal(stored.CreatedAt) || !got.CreatedAt.Equal(r.CreatedAt) {
		t.Errorf("答えの作成の日時: got %v, want データベースの値 %v", got.CreatedAt, stored.CreatedAt)
	}
	created, updated, _ := storedTimes(t, r.ID)
	if created != "2026-11-01 09:00:00.654321" || updated != "2026-11-14 10:23:45.123457" {
		t.Errorf("表の日時: 作成=%s 更新=%s", created, updated)
	}
}

// TestService_CreateResumeCopyOrdersByNewIDs は、写して作る経歴書の項目のうち、並べ方の決め手が同じ項目を、Java 版と同じく
// 新しく付けた ID の順に並べることを確かめる。コピー元の ID の順のままだと、8つの項目が新しい ID の順に並ぶことはほぼ無い。
func TestService_CreateResumeCopyOrdersByNewIDs(t *testing.T) {
	userID := insertTestUser(t)
	src := emptyResume(userID, "コピー元")
	for i := range 8 {
		src.Certifications = append(src.Certifications, Certification{ID: uuid.New(), Name: fmt.Sprintf("資格%d", i), Date: YearMonth{2020, time.April}})
	}
	saveResume(t, src)

	got, err := New(Deps{Pool: testPool, Now: fixedNow(japanTime(2026, time.December, 1, 8, 0, 0, 0))}).CreateResume(t.Context(), userID,
		jsonBody(t, map[string]any{"resumeName": "写し", "resumeId": src.ID.String()}))
	if err != nil {
		t.Fatalf("経歴書を写して作れません: %v", err)
	}
	if !slices.IsSortedFunc(got.Certifications, func(a, b Certification) int { return compareJavaUUID(a.ID, b.ID) }) {
		t.Errorf("写した資格が新しい ID の順に並んでいない: %+v", got.Certifications)
	}
	if len(got.Certifications) != len(src.Certifications) {
		t.Errorf("写した資格の数: got %d, want %d", len(got.Certifications), len(src.Certifications))
	}
	assertResume(t, mustFind(t, userID, got.ID), got)
}
