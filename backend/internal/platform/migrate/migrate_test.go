package migrate

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"slices"
	"strings"
	"sync"
	"testing"
	"testing/fstest"
)

var allVersions = []string{"1", "2", "3", "4", "5", "6", "7"}

// V1〜V7 のファイルから計算した検査の値と版と説明が、Java 版の Flyway が書いた値と同じであることを確かめる。
func TestChecksum_V1toV7(t *testing.T) {
	migrations, err := loadMigrations(migrationFS(t))
	if err != nil {
		t.Fatalf("loadMigrations: %v", err)
	}
	if len(migrations) != len(flywayHistory) {
		t.Fatalf("ファイルの数 = %d, want %d", len(migrations), len(flywayHistory))
	}
	for i, want := range flywayHistory {
		got := migrations[i]
		if got.checksum != want.checksum || got.versionText != want.version ||
			got.description != want.description || got.script != want.script {
			t.Errorf("%d 番目 = {%d %s %q %s}, want {%d %s %q %s}", i+1,
				got.checksum, got.versionText, got.description, got.script,
				want.checksum, want.version, want.description, want.script)
		}
	}
}

// 検査の値が、先頭の BOM と、改行の文字(LF、CRLF、CR)を数えないことを確かめる。
func TestChecksum_IgnoresBOMAndLineBreaks(t *testing.T) {
	want := checksum([]byte("CREATE TABLE a (id int);SELECT 1;"))
	for _, content := range []string{
		"\xEF\xBB\xBFCREATE TABLE a (id int);\nSELECT 1;\n",
		"CREATE TABLE a (id int);\r\nSELECT 1;\r\n",
		"CREATE TABLE a (id int);\rSELECT 1;",
	} {
		if got := checksum([]byte(content)); got != want {
			t.Errorf("checksum(%q) = %d, want %d", content, got, want)
		}
	}
}

// ファイルの名前から、版と説明を取り出せることと、形の違う名前を断ることを確かめる。
func TestDescription_FromFileName(t *testing.T) {
	for _, tc := range []struct{ name, version, description string }{
		{"V1__create_tables.sql", "1", "create tables"},
		{"V7__add_email_verification_columns.sql", "7", "add email verification columns"},
		{"V1_2__a_b.sql", "1.2", "a b"},
		{"V10.1__x.sql", "10.1", "x"},
	} {
		version, description, err := parseFileName(tc.name)
		if err != nil || version != tc.version || description != tc.description {
			t.Errorf("parseFileName(%q) = (%q, %q, %v), want (%q, %q, nil)", tc.name, version, description, err, tc.version, tc.description)
		}
	}
	for _, name := range []string{"R__view.sql", "V1_create.sql", "V__x.sql", "V1__x.txt", "U1__x.sql"} {
		if _, _, err := parseFileName(name); !errors.Is(err, ErrInvalidFileName) {
			t.Errorf("parseFileName(%q) の誤り = %v, want %v", name, err, ErrInvalidFileName)
		}
	}
}

// 適用済みの版の検査の値が合わないとき、ValidateOnly が誤りを返すことを確かめる。
func TestRun_ValidateOnly_ChecksumMismatch(t *testing.T) {
	pool := newDatabase(t)
	rows := slices.Clone(flywayHistory)
	rows[2].checksum = int64(12345)
	writeFlywayHistory(t, pool, rows)

	_, err := Run(t.Context(), pool, migrationFS(t), ValidateOnly)
	if !errors.Is(err, ErrChecksumMismatch) {
		t.Fatalf("Run の誤り = %v, want %v", err, ErrChecksumMismatch)
	}
}

// 履歴に success = false の行があるとき、ValidateOnly が誤りを返すことを確かめる。
func TestRun_ValidateOnly_FailedRow(t *testing.T) {
	pool := newDatabase(t)
	rows := slices.Clone(flywayHistory)
	rows[6].success = false
	writeFlywayHistory(t, pool, rows)

	_, err := Run(t.Context(), pool, migrationFS(t), ValidateOnly)
	if !errors.Is(err, ErrFailedMigration) {
		t.Fatalf("Run の誤り = %v, want %v", err, ErrFailedMigration)
	}
}

// 履歴にファイルに無い版の行があるとき、ValidateOnly が誤りを返すことを確かめる。
func TestRun_ValidateOnly_UnknownVersion(t *testing.T) {
	pool := newDatabase(t)
	rows := append(slices.Clone(flywayHistory), historyFixture{
		rank: 8, version: "8", description: "unknown", typ: "SQL", script: "V8__unknown.sql", checksum: int64(1), success: true,
	})
	writeFlywayHistory(t, pool, rows)

	_, err := Run(t.Context(), pool, migrationFS(t), ValidateOnly)
	if !errors.Is(err, ErrUnknownVersion) {
		t.Fatalf("Run の誤り = %v, want %v", err, ErrUnknownVersion)
	}
}

// ValidateOnly が、未適用の版を報告するだけで、データベースに何も書かないことを確かめる。
func TestRun_ValidateOnly_WritesNothing(t *testing.T) {
	t.Run("履歴の表が無いとき", func(t *testing.T) {
		pool := newDatabase(t)

		result, err := Run(t.Context(), pool, migrationFS(t), ValidateOnly)
		if err != nil {
			t.Fatalf("Run: %v", err)
		}
		if !slices.Equal(result.Pending, allVersions) || len(result.Validated) != 0 || len(result.Applied) != 0 {
			t.Errorf("Run の結果 = %+v, want Pending だけが %v", result, allVersions)
		}
		if tableExists(t, pool, "flyway_schema_history") || tableExists(t, pool, "users") {
			t.Error("ValidateOnly が表を作りました")
		}
	})
	t.Run("V7 が未適用のとき", func(t *testing.T) {
		pool := newDatabase(t)
		writeFlywayHistory(t, pool, flywayHistory[:6])
		before := readHistoryRows(t, pool)

		result, err := Run(t.Context(), pool, migrationFS(t), ValidateOnly)
		if err != nil {
			t.Fatalf("Run: %v", err)
		}
		if !slices.Equal(result.Validated, allVersions[:6]) || !slices.Equal(result.Pending, []string{"7"}) || len(result.Applied) != 0 {
			t.Errorf("Run の結果 = %+v, want Validated %v と Pending [7]", result, allVersions[:6])
		}
		if after := readHistoryRows(t, pool); !slices.Equal(after, before) {
			t.Errorf("履歴が変わりました\nbefore: %v\nafter:  %v", before, after)
		}
		if tableExists(t, pool, "users") {
			t.Error("ValidateOnly がマイグレーションを適用しました")
		}
	})
}

// Flyway の baseline-on-migrate が書いた行があっても、ValidateOnly が通ることを確かめる。
// 本番の Java 版は baseline-on-migrate: true と baseline-version: 0 で動くため、この行がある場合がある。
func TestRun_ValidateOnly_BaselineRow(t *testing.T) {
	pool := newDatabase(t)
	rows := []historyFixture{{
		rank: 1, version: "0", description: "<< Flyway Baseline >>", typ: "BASELINE", script: "<< Flyway Baseline >>", checksum: nil, success: true,
	}}
	for _, row := range flywayHistory {
		row.rank++
		rows = append(rows, row)
	}
	writeFlywayHistory(t, pool, rows)

	result, err := Run(t.Context(), pool, migrationFS(t), ValidateOnly)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if !slices.Equal(result.Validated, allVersions) || len(result.Pending) != 0 {
		t.Errorf("Run の結果 = %+v, want Validated %v", result, allVersions)
	}
}

// 空のデータベースに Apply で V1〜V7 を適用し、Java 版の Flyway と同じ形の行を書くことを確かめる。
func TestRun_Apply_EmptyDatabase(t *testing.T) {
	pool := newDatabase(t)

	result, err := Run(t.Context(), pool, migrationFS(t), Apply)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if !slices.Equal(result.Applied, allVersions) {
		t.Errorf("Applied = %v, want %v", result.Applied, allVersions)
	}
	if !tableExists(t, pool, "users") {
		t.Error("V1 の表 users がありません")
	}

	// installed_on と execution_time は動かすたびに変わるので、それ以外の列を比べる
	query := `SELECT concat_ws('|', installed_rank, version, description, type, script, checksum, installed_by, success)
		FROM flyway_schema_history ORDER BY installed_rank`
	rows, err := pool.Query(t.Context(), query)
	if err != nil {
		t.Fatalf("履歴を読めません: %v", err)
	}
	var got []string
	for rows.Next() {
		var line string
		if err := rows.Scan(&line); err != nil {
			t.Fatalf("履歴の行を読めません: %v", err)
		}
		got = append(got, line)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("履歴を読めません: %v", err)
	}
	var want []string
	for _, row := range flywayHistory {
		want = append(want, fmt.Sprintf("%d|%s|%s|SQL|%s|%d|postgres|t", row.rank, row.version, row.description, row.script, row.checksum))
	}
	if !slices.Equal(got, want) {
		t.Errorf("履歴の行\n got: %v\nwant: %v", got, want)
	}

	again, err := Run(t.Context(), pool, migrationFS(t), ValidateOnly)
	if err != nil || !slices.Equal(again.Validated, allVersions) || len(again.Pending) != 0 {
		t.Errorf("適用のあとの ValidateOnly = (%+v, %v), want Validated %v", again, err, allVersions)
	}
}

// 同時に動かした複数の Apply が、pg_advisory_lock で1つずつ動き、同じファイルを2回適用しないことを確かめる。
func TestRun_Apply_Concurrent(t *testing.T) {
	pool := newDatabase(t)
	files := migrationFS(t)

	const runs = 4
	results := make([]Result, runs)
	errs := make([]error, runs)
	var wg sync.WaitGroup
	for i := range runs {
		wg.Go(func() {
			results[i], errs[i] = Run(t.Context(), pool, files, Apply)
		})
	}
	wg.Wait()

	var applied []string
	for i := range runs {
		if errs[i] != nil {
			t.Errorf("%d 番目の Run: %v", i+1, errs[i])
		}
		applied = append(applied, results[i].Applied...)
	}
	slices.Sort(applied)
	if !slices.Equal(applied, allVersions) {
		t.Errorf("4つの Run が適用した版の合計 = %v, want %v", applied, allVersions)
	}
	if got := len(readHistoryRows(t, pool)); got != len(allVersions) {
		t.Errorf("履歴の行の数 = %d, want %d", got, len(allVersions))
	}
}

// 動かし方とファイルと履歴の行が扱えない形のとき、Run が何も書かずに誤りを返すことを確かめる。
func TestRun_RejectsInvalidInput(t *testing.T) {
	canceled, cancel := context.WithCancel(t.Context())
	cancel()
	ok := fstest.MapFS{"V1__ok.sql": {Data: []byte("CREATE TABLE ok_table (id int);")}}
	for _, tc := range []struct {
		name    string
		ctx     context.Context
		files   fs.FS
		mode    Mode
		history []historyFixture
		want    string
	}{
		{name: "動かし方が無い値", ctx: t.Context(), files: ok, mode: Mode(0), want: "ValidateOnly でも Apply でもありません"},
		{name: "ファイルの名前の形が違う", ctx: t.Context(), files: fstest.MapFS{"R__view.sql": {Data: []byte("SELECT 1;")}}, mode: Apply, want: ErrInvalidFileName.Error()},
		{name: "同じ版のファイルが2つある", ctx: t.Context(), files: fstest.MapFS{
			"V1__a.sql": {Data: []byte("SELECT 1;")}, "V1.0__b.sql": {Data: []byte("SELECT 1;")},
		}, mode: Apply, want: "版が同じです"},
		{name: "履歴に版の無い繰り返しの行がある", ctx: t.Context(), files: ok, mode: Apply, history: []historyFixture{
			{rank: 1, version: "", description: "view", typ: "SQL", script: "R__view.sql", checksum: int64(1), success: true},
		}, want: ErrUnsupportedRow.Error()},
		{name: "コンテキストが取り消されている", ctx: canceled, files: ok, mode: Apply, want: "データベースにつなげません"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			pool := newDatabase(t)
			if tc.history != nil {
				writeFlywayHistory(t, pool, tc.history)
				if _, err := pool.Exec(t.Context(), "UPDATE flyway_schema_history SET version = NULL WHERE version = ''"); err != nil {
					t.Fatalf("履歴の版を NULL にできません: %v", err)
				}
			}

			result, err := Run(tc.ctx, pool, tc.files, tc.mode)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("Run の誤り = %v, want %q を含む誤り", err, tc.want)
			}
			if len(result.Applied) != 0 || tableExists(t, pool, "ok_table") {
				t.Errorf("Run が適用しました: %+v", result)
			}
		})
	}
}

// 適用に失敗したファイルの変更と履歴の行が、どちらも残らないことを確かめる。
func TestRun_Apply_BrokenFileWritesNoRow(t *testing.T) {
	pool := newDatabase(t)
	files := fstest.MapFS{
		"V1__ok.sql":     {Data: []byte("CREATE TABLE ok_table (id int);")},
		"V2__broken.sql": {Data: []byte("CREATE TABLE broken_table (id int);\nSELEC 1;")},
	}

	result, err := Run(t.Context(), pool, files, Apply)
	if err == nil || !strings.Contains(err.Error(), "V2__broken.sql") {
		t.Fatalf("Run の誤り = %v, want V2__broken.sql の適用の誤り", err)
	}
	if !slices.Equal(result.Applied, []string{"1"}) {
		t.Errorf("Applied = %v, want [1]", result.Applied)
	}
	if tableExists(t, pool, "broken_table") {
		t.Error("失敗したファイルの表 broken_table が残っています")
	}
	if rows := readHistoryRows(t, pool); len(rows) != 1 || !strings.HasPrefix(rows[0], "1|1|ok|SQL|V1__ok.sql|") {
		t.Errorf("履歴の行 = %v, want V1 の1行だけ", rows)
	}
}
