package resume

import (
	"context"
	"fmt"
	"net"
	"os"
	"strconv"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/migrate"
)

// postgresImage は、開発環境の db のサービス(docker/db/Dockerfile)と同じ版の Postgres である。
const postgresImage = "postgres:17.11-alpine"

// testPool は、テストの Postgres への接続の束である。TestMain が、Java 版の Flyway と同じ表を作ってから渡す。
var testPool *pgxpool.Pool

// TestMain は、テストの全体で1つの Postgres のコンテナを動かし、backend.Migrations() のマイグレーションを流して表を作る。
// マスタと経歴書の処理は Redis と S3 を使わないので、Postgres だけを動かす。
// Docker が無いときは、テストを飛ばさずに失敗させる。
func TestMain(m *testing.M) {
	os.Exit(runTests(m))
}

func runTests(m *testing.M) int {
	ctx := context.Background()

	pg, err := postgres.Run(ctx, postgresImage,
		postgres.WithDatabase("keireki_pro"),
		postgres.WithUsername("postgres"),
		postgres.WithPassword("postgres"),
		postgres.BasicWaitStrategies(),
	)
	defer terminate("Postgres", pg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres のコンテナを動かせません: %v\n", err)
		return 1
	}
	opts, err := databaseOptions(ctx, pg)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	testPool, err = database.Open(ctx, opts)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres につなげません: %v\n", err)
		return 1
	}
	defer testPool.Close()
	files, err := backend.Migrations()
	if err != nil {
		fmt.Fprintf(os.Stderr, "マイグレーションのファイルを読めません: %v\n", err)
		return 1
	}
	if _, err := migrate.Run(ctx, testPool, files, migrate.Apply); err != nil {
		fmt.Fprintf(os.Stderr, "マイグレーションを流せません: %v\n", err)
		return 1
	}
	return m.Run()
}

// databaseOptions は、Postgres のコンテナのつなぎ先を、database.Open に渡す形にする。
func databaseOptions(ctx context.Context, pg *postgres.PostgresContainer) (database.Options, error) {
	endpoint, err := pg.PortEndpoint(ctx, "5432/tcp", "")
	if err != nil {
		return database.Options{}, fmt.Errorf("テストの Postgres のつなぎ先を読めません: %w", err)
	}
	host, portText, err := net.SplitHostPort(endpoint)
	if err != nil {
		return database.Options{}, fmt.Errorf("テストの Postgres のつなぎ先 %s を読めません: %w", endpoint, err)
	}
	port, err := strconv.Atoi(portText)
	if err != nil {
		return database.Options{}, fmt.Errorf("テストの Postgres のポート %s を読めません: %w", portText, err)
	}
	return database.Options{Host: host, Port: port, Database: "keireki_pro", User: "postgres", Password: "postgres"}, nil
}

// terminate は、テストのコンテナを止める。
func terminate(name string, c testcontainers.Container) {
	if err := testcontainers.TerminateContainer(c); err != nil {
		fmt.Fprintf(os.Stderr, "%s のコンテナを止められません: %v\n", name, err)
	}
}

// TestIntegrationSetup は、TestMain が、マスタと経歴書の処理の結合テストの土台を用意してあることを確かめる。
func TestIntegrationSetup(t *testing.T) {
	t.Run("経歴書の表とマスタの表がある", func(t *testing.T) {
		for _, table := range []string{
			"users", "resumes", "careers", "projects", "project_tech_stacks", "certifications",
			"portfolios", "sns_platforms", "self_promotions",
			"certification_mst", "sns_platform_mst", "tech_stack_category_mst", "tech_stack_mst",
		} {
			var exists bool
			if err := testPool.QueryRow(t.Context(), "SELECT to_regclass($1) IS NOT NULL", "public."+table).Scan(&exists); err != nil {
				t.Fatalf("表 %s を調べられません: %v", table, err)
			}
			if !exists {
				t.Errorf("表 %s が無い", table)
			}
		}
	})

	t.Run("マスタの行が入っている", func(t *testing.T) {
		for _, table := range []string{"certification_mst", "sns_platform_mst", "tech_stack_category_mst", "tech_stack_mst"} {
			var count int
			if err := testPool.QueryRow(t.Context(), "SELECT count(*) FROM "+table).Scan(&count); err != nil {
				t.Fatalf("表 %s の行を数えられません: %v", table, err)
			}
			if count == 0 {
				t.Errorf("表 %s に行が無い", table)
			}
		}
	})
}
