//go:build compat

package harness

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/migrate"
)

// ApplyMigrations は、connString のデータベースに、migrate の部品の Apply で V1〜V7 を適用する。
// 比べる検査は、検査の始めに各データベースにこれを1回動かす。Java 版の Flyway は起動のときに適用済みの履歴を確かめるだけになり、
// Go 版は ValidateOnly で同じ履歴を確かめる。
func ApplyMigrations(ctx context.Context, connString string) (migrate.Result, error) {
	pool, err := pgxpool.New(ctx, connString)
	if err != nil {
		return migrate.Result{}, fmt.Errorf("harness: データベースにつなげません: %w", err)
	}
	defer pool.Close()
	files, err := backend.Migrations()
	if err != nil {
		return migrate.Result{}, fmt.Errorf("harness: マイグレーションのファイルを読めません: %w", err)
	}
	result, err := migrate.Run(ctx, pool, files, migrate.Apply)
	if err != nil {
		return result, fmt.Errorf("harness: マイグレーションを適用できません: %w", err)
	}
	return result, nil
}
