package database

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
)

// postgresImage は、開発環境の db のサービス(docker/db/Dockerfile)と同じ版の Postgres である。
const postgresImage = "postgres:17.11-alpine"

// testOptions は、テストの Postgres のつなぎ先である。
var testOptions Options

// TestMain は、テストの全体で1つの Postgres のコンテナを動かす。
// Docker が無いときは、テストを飛ばさずに失敗させる。
func TestMain(m *testing.M) {
	os.Exit(runTests(m))
}

func runTests(m *testing.M) int {
	ctx := context.Background()
	container, err := postgres.Run(ctx, postgresImage,
		postgres.WithDatabase("keireki_pro"),
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
	endpoint, err := container.PortEndpoint(ctx, "5432/tcp", "")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres のつなぎ先を読めません: %v\n", err)
		return 1
	}
	host, portText, err := net.SplitHostPort(endpoint)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres のつなぎ先 %s を読めません: %v\n", endpoint, err)
		return 1
	}
	port, err := strconv.Atoi(portText)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres のポート %s を読めません: %v\n", portText, err)
		return 1
	}
	testOptions = Options{Host: host, Port: port, Database: "keireki_pro", User: "postgres", Password: "postgres"}
	return m.Run()
}

// 接続ごとに時間帯が Asia/Tokyo になり、日時を日本の時刻で読めることと、接続の最大が10であることを確かめる。
func TestPool_TimeZoneTokyo(t *testing.T) {
	pool, err := Open(t.Context(), testOptions)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(pool.Close)

	var timeZone string
	if err := pool.QueryRow(t.Context(), "SHOW TimeZone").Scan(&timeZone); err != nil {
		t.Fatalf("時間帯を読めません: %v", err)
	}
	if timeZone != "Asia/Tokyo" {
		t.Errorf("時間帯 = %q, want %q", timeZone, "Asia/Tokyo")
	}

	var local string
	if err := pool.QueryRow(t.Context(), "SELECT '2026-01-01 00:00:00+00'::timestamptz::text").Scan(&local); err != nil {
		t.Fatalf("日時を読めません: %v", err)
	}
	if local != "2026-01-01 09:00:00+09" {
		t.Errorf("日時 = %q, want %q", local, "2026-01-01 09:00:00+09")
	}

	if got := pool.Config().MaxConns; got != 10 {
		t.Errorf("接続の最大 = %d, want 10", got)
	}
}

// つなげないときの誤りに、パスワードを書かないことを確かめる。
func TestOpen_ErrorHasNoPassword(t *testing.T) {
	opts := testOptions
	opts.Password = "wrong-password-1234"
	pool, err := Open(t.Context(), opts)
	if err == nil {
		pool.Close()
		t.Fatal("Open の誤り = nil, want パスワードが違うことの誤り")
	}
	// 誤りが、データベースが返したパスワードの誤り(28P01)であることも確かめる。
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != "28P01" {
		t.Errorf("Open の誤り = %v, want データベースが返したパスワードの誤り(28P01)", err)
	}
	if strings.Contains(err.Error(), opts.Password) {
		t.Errorf("Open の誤り %q に、パスワードが書かれています", err)
	}
}
