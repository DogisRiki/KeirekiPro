package resume

import (
	"context"
	"errors"
	"reflect"
	"testing"

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
