package migrate

import (
	"slices"
	"testing"
)

// Java 版の Flyway が開発環境のデータベースに書いた履歴と同じ行を、testcontainers-go の Postgres に作り、
// Go 版が ValidateOnly で同じ履歴を引き継げることを確かめる。
func TestValidateOnly_FlywayWrittenHistory(t *testing.T) {
	pool := newDatabase(t)
	writeFlywayHistory(t, pool, flywayHistory)

	result, err := Run(t.Context(), pool, migrationFS(t), ValidateOnly)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if !slices.Equal(result.Validated, allVersions) || len(result.Pending) != 0 || len(result.Applied) != 0 {
		t.Errorf("Run の結果 = %+v, want Validated %v だけ", result, allVersions)
	}
}
