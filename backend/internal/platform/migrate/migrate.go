// Package migrate は、表の形の履歴(Flyway の flyway_schema_history)を、埋め込んだマイグレーションのファイルと照らす部品である。
// この部品は、Flyway と同じ検査の値を計算し、Apply では、未適用のファイルを版の順に適用して、Flyway と同じ形の行を書く。
// この部品は、繰り返しのマイグレーションと元に戻すマイグレーションを扱わない。
package migrate

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"hash/crc32"
	"io/fs"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Mode は、この部品の動かし方である。
type Mode int

const (
	// ValidateOnly は、履歴を確かめるだけで、データベースに何も書かない。
	ValidateOnly Mode = iota + 1
	// Apply は、履歴を確かめたうえで、未適用のファイルを版の順に1つずつ適用し、履歴に行を書く。
	Apply
)

// Result は、Run が確かめた版と、適用した版と、適用していない版である。
type Result struct {
	// Validated は、履歴に記録があり、検査の値がファイルと合った版である。
	Validated []string
	// Applied は、Apply が適用した版である。
	Applied []string
	// Pending は、ValidateOnly が見つけた、履歴に記録の無い版である。
	Pending []string
}

var (
	// ErrChecksumMismatch は、適用済みの版の検査の値が、ファイルから計算した値と合わないことを表す。
	ErrChecksumMismatch = errors.New("適用済みの版の検査の値が、ファイルの検査の値と合いません")
	// ErrFailedMigration は、履歴に、適用が失敗した行(success = false)があることを表す。
	ErrFailedMigration = errors.New("履歴に、適用が失敗した行があります")
	// ErrUnknownVersion は、履歴に、ファイルに無い版の行があることを表す。
	ErrUnknownVersion = errors.New("履歴に、ファイルに無い版の行があります")
	// ErrUnsupportedRow は、履歴に、この部品が扱わない種類の行があることを表す。
	ErrUnsupportedRow = errors.New("履歴に、この部品が扱わない種類の行があります")
	// ErrInvalidFileName は、マイグレーションのファイルの名前が V<版>__<説明>.sql の形でないことを表す。
	ErrInvalidFileName = errors.New("マイグレーションのファイルの名前が V<版>__<説明>.sql の形ではありません")
)

const (
	// historyTable は、Flyway が表の形の履歴を記録する表である。
	historyTable = "flyway_schema_history"

	// lockKey は、pg_advisory_lock の鍵の番号である。同時に起動した複数の部品が、1つずつ動くようにする。
	lockKey int64 = 4_450_700_001

	// typeSQL は、版の付いた SQL のマイグレーションの行の種類である。
	typeSQL = "SQL"
	// typeBaseline は、Flyway の baseline-on-migrate が書く行の種類である。この行の版以下のファイルは、適用済みとして扱う。
	typeBaseline = "BASELINE"

	// createHistoryTable は、Flyway(flyway-database-postgresql の PostgreSQLDatabase.getRawCreateScript)が作る表と同じ表を作る。
	createHistoryTable = `CREATE TABLE "flyway_schema_history" (
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

	// insertHistoryRow は、Flyway と同じ列に行を書く。installed_on は、表の既定の now() が入る。
	insertHistoryRow = `INSERT INTO "flyway_schema_history"
    ("installed_rank", "version", "description", "type", "script", "checksum", "installed_by", "execution_time", "success")
SELECT COALESCE(MAX("installed_rank"), 0) + 1, $1, $2, 'SQL', $3, $4, current_user, $5, true
FROM "flyway_schema_history"`

	selectHistory = `SELECT "version", "type", "checksum", "success"
FROM "flyway_schema_history" ORDER BY "installed_rank"`
)

// fileNamePattern は、版の付いたマイグレーションのファイルの名前の形である。版の区切りには . と _ を使える。
var fileNamePattern = regexp.MustCompile(`^V(\d+(?:[._]\d+)*)__(.+)\.sql$`)

// utf8BOM は、UTF-8 で書かれたことを示すために、ファイルの先頭に置かれることがある3バイトである。
var utf8BOM = []byte{0xEF, 0xBB, 0xBF}

// migration は、1つのマイグレーションのファイルである。
type migration struct {
	version     []uint64
	versionText string
	description string
	script      string
	checksum    int64
	sql         string
}

// historyRow は、履歴の1行のうち、照らすのに使う列である。
type historyRow struct {
	version  *string
	typ      string
	checksum *int64
	success  bool
}

// Run は、履歴をマイグレーションのファイルと照らす。mode が Apply のときは、未適用のファイルを版の順に適用する。
// Run は、同時に起動したほかの Run と、pg_advisory_lock で1つずつ動く。
func Run(ctx context.Context, pool *pgxpool.Pool, files fs.FS, mode Mode) (result Result, err error) {
	if mode != ValidateOnly && mode != Apply {
		return Result{}, fmt.Errorf("migrate: 動かし方 %d は ValidateOnly でも Apply でもありません", mode)
	}
	migrations, err := loadMigrations(files)
	if err != nil {
		return Result{}, err
	}

	conn, err := pool.Acquire(ctx)
	if err != nil {
		return Result{}, fmt.Errorf("migrate: データベースにつなげません: %w", err)
	}
	defer conn.Release()

	if _, err := conn.Exec(ctx, "SELECT pg_advisory_lock($1)", lockKey); err != nil {
		return Result{}, fmt.Errorf("migrate: 鍵を取れません: %w", err)
	}
	defer func() {
		if _, unlockErr := conn.Exec(context.WithoutCancel(ctx), "SELECT pg_advisory_unlock($1)", lockKey); unlockErr != nil {
			err = errors.Join(err, fmt.Errorf("migrate: 鍵を放せません: %w", unlockErr))
		}
	}()

	var exists bool
	if err := conn.QueryRow(ctx, "SELECT to_regclass($1) IS NOT NULL", historyTable).Scan(&exists); err != nil {
		return Result{}, fmt.Errorf("migrate: 履歴の表があるかを確かめられません: %w", err)
	}
	var history []historyRow
	switch {
	case exists:
		if history, err = readHistory(ctx, conn); err != nil {
			return Result{}, err
		}
	case mode == Apply:
		if _, err := conn.Exec(ctx, createHistoryTable); err != nil {
			return Result{}, fmt.Errorf("migrate: 履歴の表を作れません: %w", err)
		}
	}

	validated, pending, err := compare(migrations, history)
	if err != nil {
		return Result{}, err
	}
	result.Validated = versionTexts(validated)
	if mode == ValidateOnly {
		result.Pending = versionTexts(pending)
		return result, nil
	}
	for _, m := range pending {
		if err := applyOne(ctx, conn, m); err != nil {
			return result, err
		}
		result.Applied = append(result.Applied, m.versionText)
	}
	return result, nil
}

// loadMigrations は、files の最上位のファイルを読み、版の順に並べる。
func loadMigrations(files fs.FS) ([]migration, error) {
	entries, err := fs.ReadDir(files, ".")
	if err != nil {
		return nil, fmt.Errorf("migrate: マイグレーションのファイルの一覧を読めません: %w", err)
	}
	migrations := make([]migration, 0, len(entries))
	seen := map[string]string{}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		versionText, description, err := parseFileName(name)
		if err != nil {
			return nil, err
		}
		version, err := parseVersion(versionText)
		if err != nil {
			return nil, fmt.Errorf("migrate: %s: %w", name, err)
		}
		key := versionKey(version)
		if other, ok := seen[key]; ok {
			return nil, fmt.Errorf("migrate: %s と %s の版が同じです", other, name)
		}
		seen[key] = name
		content, err := fs.ReadFile(files, name)
		if err != nil {
			return nil, fmt.Errorf("migrate: %s を読めません: %w", name, err)
		}
		migrations = append(migrations, migration{
			version:     version,
			versionText: versionText,
			description: description,
			script:      name,
			checksum:    checksum(content),
			sql:         string(bytes.TrimPrefix(content, utf8BOM)),
		})
	}
	slices.SortFunc(migrations, func(a, b migration) int { return compareVersions(a.version, b.version) })
	return migrations, nil
}

// parseFileName は、ファイルの名前から、版と説明を取り出す。
// 版は、区切りの _ を . にしたものである。説明は、V<版>__ と .sql を除き、_ を空白にしたものである。
func parseFileName(name string) (versionText, description string, err error) {
	match := fileNamePattern.FindStringSubmatch(name)
	if match == nil {
		return "", "", fmt.Errorf("migrate: %s: %w", name, ErrInvalidFileName)
	}
	return strings.ReplaceAll(match[1], "_", "."), strings.ReplaceAll(match[2], "_", " "), nil
}

// parseVersion は、. で区切った版を、数の並びにする。末尾の 0 は除く(Flyway では 1 と 1.0 は同じ版である)。
func parseVersion(text string) ([]uint64, error) {
	parts := strings.Split(text, ".")
	version := make([]uint64, 0, len(parts))
	for _, part := range parts {
		n, err := strconv.ParseUint(part, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("版 %q を読めません: %w", text, err)
		}
		version = append(version, n)
	}
	for len(version) > 1 && version[len(version)-1] == 0 {
		version = version[:len(version)-1]
	}
	return version, nil
}

// versionKey は、版を、同じ版なら同じになる文字列にする。
func versionKey(version []uint64) string {
	parts := make([]string, len(version))
	for i, n := range version {
		parts[i] = strconv.FormatUint(n, 10)
	}
	return strings.Join(parts, ".")
}

// compareVersions は、版を数の並びとして比べる。
func compareVersions(a, b []uint64) int {
	for i := range max(len(a), len(b)) {
		var x, y uint64
		if i < len(a) {
			x = a[i]
		}
		if i < len(b) {
			y = b[i]
		}
		if x != y {
			if x < y {
				return -1
			}
			return 1
		}
	}
	return 0
}

// checksum は、Flyway と同じ検査の値を計算する。
// Flyway は、先頭の BOM を除き、行ごとに改行を除いた文字列を CRC32(IEEE)に順に入れ、結果を符号付きの32ビットの整数にする。
// 行を順に入れることは、改行を除いた全体を入れることと同じなので、ここでは改行の文字を飛ばして入れる。
func checksum(content []byte) int64 {
	content = bytes.TrimPrefix(content, utf8BOM)
	var crc uint32
	start := 0
	for i, c := range content {
		if c == '\n' || c == '\r' {
			crc = crc32.Update(crc, crc32.IEEETable, content[start:i])
			start = i + 1
		}
	}
	crc = crc32.Update(crc, crc32.IEEETable, content[start:])
	sum := int64(crc)
	if sum >= 1<<31 {
		sum -= 1 << 32
	}
	return sum
}

// readHistory は、履歴の行を installed_rank の順に読む。
func readHistory(ctx context.Context, conn *pgxpool.Conn) ([]historyRow, error) {
	rows, err := conn.Query(ctx, selectHistory)
	if err != nil {
		return nil, fmt.Errorf("migrate: 履歴を読めません: %w", err)
	}
	defer rows.Close()
	var history []historyRow
	for rows.Next() {
		var row historyRow
		if err := rows.Scan(&row.version, &row.typ, &row.checksum, &row.success); err != nil {
			return nil, fmt.Errorf("migrate: 履歴の行を読めません: %w", err)
		}
		history = append(history, row)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("migrate: 履歴を読めません: %w", err)
	}
	return history, nil
}

// compare は、履歴の行をファイルと照らし、確かめた版と、適用していない版を、版の順に返す。
func compare(migrations []migration, history []historyRow) (validated, pending []migration, err error) {
	byKey := make(map[string]migration, len(migrations))
	for _, m := range migrations {
		byKey[versionKey(m.version)] = m
	}
	applied := map[string]bool{}
	var baseline []uint64
	for _, row := range history {
		label := "(版なし)"
		if row.version != nil {
			label = *row.version
		}
		if !row.success {
			return nil, nil, fmt.Errorf("migrate: 版 %s: %w", label, ErrFailedMigration)
		}
		if row.version == nil || (row.typ != typeSQL && row.typ != typeBaseline) {
			return nil, nil, fmt.Errorf("migrate: 版 %s の種類 %s: %w", label, row.typ, ErrUnsupportedRow)
		}
		version, err := parseVersion(*row.version)
		if err != nil {
			return nil, nil, fmt.Errorf("migrate: 履歴の%w", err)
		}
		if row.typ == typeBaseline {
			baseline = version
			continue
		}
		m, ok := byKey[versionKey(version)]
		if !ok {
			return nil, nil, fmt.Errorf("migrate: 版 %s: %w", label, ErrUnknownVersion)
		}
		if row.checksum == nil || *row.checksum != m.checksum {
			recorded := "NULL"
			if row.checksum != nil {
				recorded = strconv.FormatInt(*row.checksum, 10)
			}
			return nil, nil, fmt.Errorf("migrate: 版 %s の履歴は %s、%s は %d: %w", label, recorded, m.script, m.checksum, ErrChecksumMismatch)
		}
		applied[versionKey(version)] = true
		validated = append(validated, m)
	}
	for _, m := range migrations {
		if applied[versionKey(m.version)] || (baseline != nil && compareVersions(m.version, baseline) <= 0) {
			continue
		}
		pending = append(pending, m)
	}
	return validated, pending, nil
}

// applyOne は、1つのファイルの適用と履歴の行の記録を、1つのトランザクションで行う。
func applyOne(ctx context.Context, conn *pgxpool.Conn, m migration) error {
	tx, err := conn.Begin(ctx)
	if err != nil {
		return fmt.Errorf("migrate: %s のトランザクションを始められません: %w", m.script, err)
	}
	defer func() { _ = tx.Rollback(context.WithoutCancel(ctx)) }()

	start := time.Now()
	// 引数の無い Exec は、1つの文字列の複数の文を送れる単純な問い合わせで送られる。
	if _, err := tx.Exec(ctx, m.sql); err != nil {
		return fmt.Errorf("migrate: %s を適用できません: %w", m.script, err)
	}
	elapsed := time.Since(start).Milliseconds()
	if _, err := tx.Exec(ctx, insertHistoryRow, m.versionText, m.description, m.script, m.checksum, elapsed); err != nil {
		return fmt.Errorf("migrate: %s の履歴を書けません: %w", m.script, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("migrate: %s を確定できません: %w", m.script, err)
	}
	return nil
}

func versionTexts(migrations []migration) []string {
	texts := make([]string, 0, len(migrations))
	for _, m := range migrations {
		texts = append(texts, m.versionText)
	}
	return texts
}
