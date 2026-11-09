package migrate

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"sync/atomic"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"

	"github.com/DogisRiki/KeirekiPro/backend"
)

// postgresImage は、開発環境の db のサービス(docker/db/Dockerfile)と同じ版の Postgres である。
const postgresImage = "postgres:17.11-alpine"

var (
	// adminPool は、テストごとのデータベースを作るための接続である。
	adminPool *pgxpool.Pool
	// baseConfig は、テストの Postgres への接続の設定である。テストごとに、データベースの名前だけを替えて使う。
	baseConfig *pgxpool.Config
	// databaseSeq は、テストごとのデータベースの名前に付ける番号である。
	databaseSeq atomic.Int64
)

// TestMain は、テストの全体で1つの Postgres のコンテナを動かす。
// Docker が無いときは、テストを飛ばさずに失敗させる。
func TestMain(m *testing.M) {
	os.Exit(runTests(m))
}

func runTests(m *testing.M) int {
	ctx := context.Background()
	container, err := postgres.Run(ctx, postgresImage,
		postgres.WithDatabase("migrate"),
		postgres.WithUsername("postgres"),
		postgres.WithPassword("postgres"),
		postgres.BasicWaitStrategies(),
	)
	defer func() {
		if err := testcontainers.TerminateContainer(container); err != nil {
			fmt.Fprintf(os.Stderr, "Postgres のコンテナを止められません: %v\n", err)
		}
	}()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres のコンテナを動かせません: %v\n", err)
		return 1
	}
	connString, err := container.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres への接続の文字列を作れません: %v\n", err)
		return 1
	}
	baseConfig, err = pgxpool.ParseConfig(connString)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres への接続の文字列を読めません: %v\n", err)
		return 1
	}
	adminPool, err = pgxpool.NewWithConfig(ctx, baseConfig)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres につなげません: %v\n", err)
		return 1
	}
	defer adminPool.Close()
	return m.Run()
}

// newDatabase は、テストのための空のデータベースを作り、そこへの接続を返す。
func newDatabase(t *testing.T) *pgxpool.Pool {
	t.Helper()
	name := fmt.Sprintf("test_%d", databaseSeq.Add(1))
	if _, err := adminPool.Exec(t.Context(), "CREATE DATABASE "+pgx.Identifier{name}.Sanitize()); err != nil {
		t.Fatalf("データベース %s を作れません: %v", name, err)
	}
	config := baseConfig.Copy()
	config.ConnConfig.Database = name
	pool, err := pgxpool.NewWithConfig(t.Context(), config)
	if err != nil {
		t.Fatalf("データベース %s につなげません: %v", name, err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// migrationFS は、backend のモジュールに埋め込んだ V1〜V7 のマイグレーションのファイルを返す。
func migrationFS(t *testing.T) fs.FS {
	t.Helper()
	files, err := backend.Migrations()
	if err != nil {
		t.Fatalf("マイグレーションのファイルを読めません: %v", err)
	}
	return files
}

// flywayHistory は、開発環境のデータベースで Java 版の Flyway が書いた flyway_schema_history の行である。
// 検査の値は、research.md の「Flyway の検査の値」に書いた7つの値である。
var flywayHistory = []historyFixture{
	{rank: 1, version: "1", description: "create tables", typ: "SQL", script: "V1__create_tables.sql", checksum: int64(307357257), success: true},
	{rank: 2, version: "2", description: "insert mst data", typ: "SQL", script: "V2__insert_mst_data.sql", checksum: int64(-1507682078), success: true},
	{rank: 3, version: "3", description: "create user token versions", typ: "SQL", script: "V3__create_user_token_versions.sql", checksum: int64(1416944501), success: true},
	{rank: 4, version: "4", description: "update master data", typ: "SQL", script: "V4__update_master_data.sql", checksum: int64(987836944), success: true},
	{rank: 5, version: "5", description: "allow nullable portfolio tech stack", typ: "SQL", script: "V5__allow_nullable_portfolio_tech_stack.sql", checksum: int64(1592927299), success: true},
	{rank: 6, version: "6", description: "change project portfolio text columns to text", typ: "SQL", script: "V6__change_project_portfolio_text_columns_to_text.sql", checksum: int64(2070947832), success: true},
	{rank: 7, version: "7", description: "add email verification columns", typ: "SQL", script: "V7__add_email_verification_columns.sql", checksum: int64(1678842263), success: true},
}

// historyFixture は、テストが flyway_schema_history に書く1行である。checksum は、int64 か、NULL を表す nil である。
type historyFixture struct {
	rank        int
	version     string
	description string
	typ         string
	script      string
	checksum    any
	success     bool
}

// flywayCreateTable は、Flyway(flyway-database-postgresql の PostgreSQLDatabase.getRawCreateScript)が作る履歴の表である。
// この部品の表の作り方と別に、テストの側に書き写しておく。
const flywayCreateTable = `CREATE TABLE "flyway_schema_history" (
    "installed_rank" INT NOT NULL,
    "version" VARCHAR(50),
    "description" VARCHAR(200) NOT NULL,
    "type" VARCHAR(20) NOT NULL,
    "script" VARCHAR(1000) NOT NULL,
    "checksum" INTEGER,
    "installed_by" VARCHAR(100) NOT NULL,
    "installed_on" TIMESTAMP NOT NULL DEFAULT now(),
    "execution_time" INTEGER NOT NULL,
    "success" BOOLEAN NOT NULL
);
ALTER TABLE "flyway_schema_history" ADD CONSTRAINT "flyway_schema_history_pk" PRIMARY KEY ("installed_rank");
CREATE INDEX "flyway_schema_history_s_idx" ON "flyway_schema_history" ("success");`

// writeFlywayHistory は、Java 版の Flyway が書いた形の履歴の表を作り、rows を書く。
func writeFlywayHistory(t *testing.T, pool *pgxpool.Pool, rows []historyFixture) {
	t.Helper()
	if _, err := pool.Exec(t.Context(), flywayCreateTable); err != nil {
		t.Fatalf("履歴の表を作れません: %v", err)
	}
	for _, row := range rows {
		if _, err := pool.Exec(t.Context(),
			`INSERT INTO flyway_schema_history
			(installed_rank, version, description, type, script, checksum, installed_by, execution_time, success)
			VALUES ($1, $2, $3, $4, $5, $6, 'postgres', 12, $7)`,
			row.rank, row.version, row.description, row.typ, row.script, row.checksum, row.success); err != nil {
			t.Fatalf("履歴の行を書けません: %v", err)
		}
	}
}

// readHistoryRows は、履歴の表のすべての行を、列を | でつないだ文字列にして installed_rank の順に返す。
func readHistoryRows(t *testing.T, pool *pgxpool.Pool) []string {
	t.Helper()
	rows, err := pool.Query(t.Context(), `SELECT concat_ws('|', installed_rank, coalesce(version, ''), description, type, script,
		coalesce(checksum::text, 'NULL'), installed_by, installed_on, execution_time, success)
		FROM flyway_schema_history ORDER BY installed_rank`)
	if err != nil {
		t.Fatalf("履歴を読めません: %v", err)
	}
	lines, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		t.Fatalf("履歴を読めません: %v", err)
	}
	return lines
}

// tableExists は、名前の表がデータベースにあるかを返す。
func tableExists(t *testing.T, pool *pgxpool.Pool, name string) bool {
	t.Helper()
	var exists bool
	if err := pool.QueryRow(t.Context(), "SELECT to_regclass($1) IS NOT NULL", name).Scan(&exists); err != nil {
		t.Fatalf("表 %s があるかを確かめられません: %v", name, err)
	}
	return exists
}
