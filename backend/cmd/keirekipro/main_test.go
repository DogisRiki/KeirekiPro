package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/awsclient"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/migrate"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/pdf"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

const (
	// postgresImage と valkeyImage は、開発環境の db と redis のサービスと同じ版である。
	postgresImage = "postgres:17.11-alpine"
	valkeyImage   = "valkey/valkey:8.0.12-alpine"
	// valueDB は、テストの Postgres の利用者のパスワードである。ログに書かれないことを確かめる。
	valueDB = "main-test-db-value"
	// valueGoogle は、外部のログインの秘密の値である。ログに書かれないことを確かめる。
	valueGoogle = "main-test-google-value"
)

var (
	// adminPool は、テストごとのデータベースを作るための接続である。
	adminPool *pgxpool.Pool
	// dbHost と dbPort は、テストの Postgres のつなぎ先である。
	dbHost, dbPort string
	// redisHost と redisPort は、テストの Valkey のつなぎ先である。
	redisHost, redisPort string
	// httpClient は、テストが受け口に要求を送るクライアントである。テストは受け口を開いてから入口に渡すので、
	// 入口が要求を受け始める前でも接続はできる。期限を付けて、応答を待ち続けないようにする。
	httpClient = &http.Client{Timeout: 5 * time.Second}
	// databaseSeq は、テストごとのデータベースの名前に付ける番号である。
	databaseSeq atomic.Int64
)

// TestMain は、テストの全体で1つの Postgres と1つの Valkey のコンテナを動かす。
// Docker が無いときは、テストを飛ばさずに失敗させる。
func TestMain(m *testing.M) {
	os.Exit(runTests(m))
}

func runTests(m *testing.M) int {
	ctx := context.Background()
	pg, err := postgres.Run(ctx, postgresImage,
		postgres.WithDatabase("keireki_pro"),
		postgres.WithUsername("postgres"),
		postgres.WithPassword(valueDB),
		postgres.BasicWaitStrategies(),
	)
	defer terminate(pg, "Postgres")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres のコンテナを動かせません: %v\n", err)
		return 1
	}
	valkey, err := testcontainers.Run(ctx, valkeyImage,
		testcontainers.WithExposedPorts("6379/tcp"),
		testcontainers.WithWaitStrategy(wait.ForListeningPort("6379/tcp")),
	)
	defer terminate(valkey, "Valkey")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Valkey のコンテナを動かせません: %v\n", err)
		return 1
	}

	if dbHost, dbPort, err = endpoint(ctx, pg, "5432/tcp"); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if redisHost, redisPort, err = endpoint(ctx, valkey, "6379/tcp"); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	connString, err := pg.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres への接続の文字列を作れません: %v\n", err)
		return 1
	}
	adminPool, err = pgxpool.New(ctx, connString)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres につなげません: %v\n", err)
		return 1
	}
	defer adminPool.Close()
	return m.Run()
}

func terminate(container testcontainers.Container, name string) {
	if err := testcontainers.TerminateContainer(container); err != nil {
		fmt.Fprintf(os.Stderr, "%s のコンテナを止められません: %v\n", name, err)
	}
}

// endpoint は、コンテナのポートのつなぎ先を、ホストとポートに分けて返す。
func endpoint(ctx context.Context, container testcontainers.Container, port string) (string, string, error) {
	hostPort, err := container.PortEndpoint(ctx, port, "")
	if err != nil {
		return "", "", fmt.Errorf("%s のつなぎ先を読めません: %w", port, err)
	}
	host, p, err := net.SplitHostPort(hostPort)
	if err != nil {
		return "", "", fmt.Errorf("つなぎ先 %s を読めません: %w", hostPort, err)
	}
	return host, p, nil
}

// newDatabase は、テストのための空のデータベースを作り、その名前を返す。
func newDatabase(t *testing.T) string {
	t.Helper()
	name := fmt.Sprintf("main_%d", databaseSeq.Add(1))
	if _, err := adminPool.Exec(t.Context(), "CREATE DATABASE "+pgx.Identifier{name}.Sanitize()); err != nil {
		t.Fatalf("データベース %s を作れません: %v", name, err)
	}
	return name
}

// connect は、テストのデータベース name につなぐ。つないだ接続は、テストの終わりに閉じる。
func connect(t *testing.T, name string) *pgxpool.Pool {
	t.Helper()
	pool, err := pgxpool.New(t.Context(), fmt.Sprintf("postgres://postgres:%s@%s/%s?sslmode=disable",
		valueDB, net.JoinHostPort(dbHost, dbPort), name))
	if err != nil {
		t.Fatalf("データベースにつなげません: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// fakeSecretsManager は、Secrets Manager の GetSecretValue に、secrets の値で答えるサーバである。
func fakeSecretsManager(t *testing.T, secrets map[string]string) string {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var input struct{ SecretId string }
		if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
			t.Errorf("要求の本文を読めません: %v", err)
		}
		w.Header().Set("Content-Type", "application/x-amz-json-1.1")
		value, ok := secrets[input.SecretId]
		if !ok {
			w.Header().Set("X-Amzn-ErrorType", "ResourceNotFoundException")
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"__type":"ResourceNotFoundException","message":"not found"}`))
			return
		}
		body, err := json.Marshal(map[string]string{"Name": input.SecretId, "SecretString": value})
		if err != nil {
			t.Errorf("応答を作れません: %v", err)
		}
		_, _ = w.Write(body)
	}))
	t.Cleanup(server.Close)
	return server.URL
}

// oidcSecrets は、test の環境でも Secrets Manager から読む、外部のログインの2つの秘密の値である。
func oidcSecrets() map[string]string {
	return map[string]string{
		"keirekipro/oidc/google": `{"client_id":"google-id","client_secret":"` + valueGoogle + `"}`,
		"keirekipro/oidc/github": `{"client_id":"github-id","client_secret":"github-value"}`,
	}
}

// testEnv は、テストの Postgres と Valkey と偽の Secrets Manager につなぐ環境変数である。
func testEnv(t *testing.T, database string) map[string]string {
	t.Helper()
	return map[string]string{
		"KEIREKIPRO_ENV":          "test",
		"KEIREKIPRO_AWS_ENDPOINT": fakeSecretsManager(t, oidcSecrets()),
		"DB_HOST":                 dbHost,
		"DB_PORT":                 dbPort,
		"DB_NAME":                 database,
		"DB_USERNAME":             "postgres",
		"DB_PASSWORD":             valueDB,
		"REDIS_HOST":              redisHost,
		"REDIS_PORT":              redisPort,
	}
}

// logBuffer は、入口とテストが同時に使えるログの書き先である。
type logBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *logBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *logBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// records は、書かれたログを1行ずつ JSON として読む。
func (b *logBuffer) records(t *testing.T) []map[string]any {
	t.Helper()
	var lines []map[string]any
	for line := range strings.SplitSeq(strings.TrimSpace(b.String()), "\n") {
		if line == "" {
			continue
		}
		var record map[string]any
		if err := json.Unmarshal([]byte(line), &record); err != nil {
			t.Fatalf("ログの行 %q を読めません: %v", line, err)
		}
		lines = append(lines, record)
	}
	return lines
}

// find は、message が event のログの行を返す。無ければ nil を返す。
func (b *logBuffer) find(t *testing.T, event string) map[string]any {
	t.Helper()
	for _, record := range b.records(t) {
		if record["message"] == event {
			return record
		}
	}
	return nil
}

// field は、入れ子の項目を、点で区切った名前で取り出す。
func field(record map[string]any, path string) any {
	var current any = record
	for name := range strings.SplitSeq(path, ".") {
		next, ok := current.(map[string]any)
		if !ok {
			return nil
		}
		current = next[name]
	}
	return current
}

// harness は、テストが入口に渡すつなぎ方と、ログと、受け口の宛先である。
type harness struct {
	deps   deps
	logs   *logBuffer
	addr   string
	listen atomic.Bool
	// store は、入口が作った Redis のクライアントである。入口が終わったあと、閉じられたかを確かめる。
	store redis.UniversalClient
}

// newHarness は、env の環境変数と本当の部品で入口を動かすつなぎ方を作る。受け口は 127.0.0.1 の空いたポートで開く。
func newHarness(t *testing.T, env map[string]string) *harness {
	t.Helper()
	h := &harness{logs: &logBuffer{}}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("受け口を開けません: %v", err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	h.addr = listener.Addr().String()
	h.deps = deps{
		lookup: func(key string) (string, bool) {
			value, ok := env[key]
			return value, ok
		},
		stdout: h.logs,
		listen: func() (net.Listener, error) {
			h.listen.Store(true)
			return listener, nil
		},
		migrations: backend.Migrations,
		newRedis: func(opts redisstore.Options) redis.UniversalClient {
			h.store = redisstore.New(opts)
			return h.store
		},
		newAWS:          awsclient.New,
		newPDF:          pdf.New,
		shutdownTimeout: 30 * time.Second,
	}
	return h
}

// runOnce は、起動が失敗する入口を動かし、終了コードを返す。1分で終わらなければ失敗にする。
func (h *harness) runOnce(t *testing.T) int {
	t.Helper()
	done := make(chan int, 1)
	go func() { done <- run(t.Context(), h.deps) }()
	select {
	case code := <-done:
		return code
	case <-time.After(time.Minute):
		t.Fatal("入口が1分で終わりません")
		return -1
	}
}

// start は、入口を動かし、受け口が要求に答えるまで待つ。返す関数は、SIGTERM の代わりに context を終わらせる。
func (h *harness) start(t *testing.T) (stop context.CancelFunc, done <-chan int) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	exited := make(chan int, 1)
	go func() { exited <- run(ctx, h.deps) }()
	deadline := time.Now().Add(time.Minute)
	for {
		select {
		case code := <-exited:
			t.Fatalf("入口が、起動の途中で %d で終わりました: %s", code, h.logs.String())
		default:
		}
		if res, err := httpClient.Get("http://" + h.addr + "/healthz"); err == nil {
			_ = res.Body.Close()
			if res.StatusCode == http.StatusOK {
				return cancel, exited
			}
		}
		if time.Now().After(deadline) {
			t.Fatalf("受け口が1分で答えません: %s", h.logs.String())
		}
		time.Sleep(100 * time.Millisecond)
	}
}

// assertFailed は、入口が1で終わり、event のログに reason を含む誤りを ERROR で書いたことを確かめる。
func assertFailed(t *testing.T, h *harness, code int, event, reason string) {
	t.Helper()
	if code != 1 {
		t.Errorf("終了コード = %d, want 1", code)
	}
	record := h.logs.find(t, event)
	if record == nil {
		t.Fatalf("%s のログがありません: %s", event, h.logs.String())
	}
	message, _ := field(record, "error.message").(string)
	if !strings.Contains(message, reason) || field(record, "log.level") != "ERROR" || field(record, "service.name") != "keirekipro" {
		t.Errorf("%s のログ = %v, want ERROR で、誤りの文に %q を含む", event, record, reason)
	}
	for _, secret := range []string{valueDB, valueGoogle} {
		if strings.Contains(h.logs.String(), secret) {
			t.Errorf("ログに秘密の値を書いています: %s", h.logs.String())
		}
	}
}

// closedPort は、何も待ち受けていない 127.0.0.1 のポートを返す。
func closedPort(t *testing.T) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("ポートを選べません: %v", err)
	}
	_, port, _ := net.SplitHostPort(listener.Addr().String())
	if err := listener.Close(); err != nil {
		t.Fatalf("ポートを閉じられません: %v", err)
	}
	return port
}

// 表の形の履歴が合わないときは、受け口を開かずに、終了コード1で終わることを確かめる。
func TestRun_ExitsWithCode1OnMigrateError(t *testing.T) {
	name := newDatabase(t)
	env := testEnv(t, name)
	pool := connect(t, name)
	files, err := backend.Migrations()
	if err != nil {
		t.Fatalf("マイグレーションのファイルを読めません: %v", err)
	}
	if _, err := migrate.Run(t.Context(), pool, files, migrate.Apply); err != nil {
		t.Fatalf("V1〜V7 を適用できません: %v", err)
	}
	if _, err := pool.Exec(t.Context(), `UPDATE flyway_schema_history SET checksum = checksum + 1 WHERE version = '1'`); err != nil {
		t.Fatalf("履歴を書き換えられません: %v", err)
	}

	h := newHarness(t, env)
	assertFailed(t, h, h.runOnce(t), "startup_failed", "表の形の履歴を確かめられません")
	if message, _ := field(h.logs.find(t, "startup_failed"), "error.message").(string); !strings.Contains(message, migrate.ErrChecksumMismatch.Error()) {
		t.Errorf("誤りの文 = %q, want 検査の値が合わないこと", message)
	}
	if h.listen.Load() {
		t.Error("履歴が合わないのに、受け口を開きました")
	}

	t.Run("履歴が合えば、表を変えずに起動する", func(t *testing.T) {
		if _, err := pool.Exec(t.Context(), `UPDATE flyway_schema_history SET checksum = checksum - 1 WHERE version = '1'`); err != nil {
			t.Fatalf("履歴を戻せません: %v", err)
		}
		h := newHarness(t, env)
		stop, done := h.start(t)
		stop()
		if code := <-done; code != 0 {
			t.Errorf("終了コード = %d, want 0", code)
		}
		if record := h.logs.find(t, "migration_validated"); field(record, "validated") != float64(7) {
			t.Errorf("確かめた版のログ = %v, want 7つ", record)
		}
	})

	t.Run("空のデータベースでは、表を作らずに起動する", func(t *testing.T) {
		name := newDatabase(t)
		h := newHarness(t, testEnv(t, name))
		stop, done := h.start(t)
		stop()
		if code := <-done; code != 0 {
			t.Errorf("終了コード = %d, want 0", code)
		}
		if pending, _ := field(h.logs.find(t, "migration_validated"), "pending").([]any); len(pending) != 7 {
			t.Errorf("まだ当てていない版 = %v, want 7つ", pending)
		}
		var table *string
		if err := connect(t, name).QueryRow(t.Context(), `SELECT to_regclass('public.flyway_schema_history')::text`).Scan(&table); err != nil {
			t.Fatalf("表の有無を読めません: %v", err)
		}
		if table != nil {
			t.Errorf("入口が表 %s を作りました", *table)
		}
	})
}

// データベースか Redis につなげないときは、受け口を開かずに、終了コード1で終わることを確かめる。
func TestRun_ExitsWithCode1OnDBUnreachable(t *testing.T) {
	env := testEnv(t, newDatabase(t))
	env["DB_HOST"], env["DB_PORT"] = "127.0.0.1", closedPort(t)
	h := newHarness(t, env)
	assertFailed(t, h, h.runOnce(t), "startup_failed", "データベースにつなげません")
	if h.listen.Load() {
		t.Error("データベースにつなげないのに、受け口を開きました")
	}

	t.Run("Redis につなげない", func(t *testing.T) {
		env := testEnv(t, newDatabase(t))
		env["REDIS_HOST"], env["REDIS_PORT"] = "127.0.0.1", closedPort(t)
		h := newHarness(t, env)
		assertFailed(t, h, h.runOnce(t), "startup_failed", "Redis につなげません")
		if h.listen.Load() {
			t.Error("Redis につなげないのに、受け口を開きました")
		}
	})
}

// 起動の各段階の失敗で、理由を ERROR のログに書き、秘密の値を書かずに、終了コード1で終わることを確かめる。
func TestRun_LogsStartupFailureReason(t *testing.T) {
	broken := errors.New("壊れた部品")
	tests := []struct {
		name   string
		change func(t *testing.T, env map[string]string, d *deps)
		reason string
	}{
		{"環境の名前が誤り", func(_ *testing.T, env map[string]string, _ *deps) { env["KEIREKIPRO_ENV"] = "staging" }, "設定を読めません"},
		{"秘密の値が無い", func(t *testing.T, env map[string]string, _ *deps) {
			env["KEIREKIPRO_AWS_ENDPOINT"] = fakeSecretsManager(t, map[string]string{})
		}, "秘密の値 keirekipro/oidc/google を読めません"},
		{"マイグレーションのファイルを読めない", func(_ *testing.T, _ map[string]string, d *deps) {
			d.migrations = func() (fs.FS, error) { return nil, broken }
		}, "マイグレーションのファイルを読めません: 壊れた部品"},
		{"AWS のクライアントを作れない", func(_ *testing.T, _ map[string]string, d *deps) {
			d.newAWS = func(context.Context, awsclient.Options) (awsclient.Clients, error) {
				return awsclient.Clients{}, broken
			}
		}, "AWS のクライアントを作れません: 壊れた部品"},
		{"PDF を作る部品を起動できない", func(_ *testing.T, _ map[string]string, d *deps) {
			d.newPDF = func(pdf.Options) (*pdf.Engine, error) { return nil, broken }
		}, "PDF を作る部品を起動できません: 壊れた部品"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			env := testEnv(t, newDatabase(t))
			h := newHarness(t, env)
			tt.change(t, env, &h.deps)
			assertFailed(t, h, h.runOnce(t), "startup_failed", tt.reason)
			if h.listen.Load() {
				t.Error("起動が失敗したのに、受け口を開きました")
			}
		})
	}

	t.Run("受け口を開けない", func(t *testing.T) {
		h := newHarness(t, testEnv(t, newDatabase(t)))
		h.deps.listen = func() (net.Listener, error) { return nil, broken }
		assertFailed(t, h, h.runOnce(t), "startup_failed", "HTTP の受け口を開けません: 壊れた部品")
	})

	t.Run("受け口が要求を受けられない", func(t *testing.T) {
		h := newHarness(t, testEnv(t, newDatabase(t)))
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			t.Fatalf("受け口を開けません: %v", err)
		}
		if err := listener.Close(); err != nil {
			t.Fatalf("受け口を閉じられません: %v", err)
		}
		h.deps.listen = func() (net.Listener, error) { return listener, nil }
		assertFailed(t, h, h.runOnce(t), "serve_failed", "HTTP の受け口が止まりました")
	})
}

// resources は、動いている Chromium の処理の数と、データベース name への接続の数と、Redis への接続の数を返す。
// Redis への接続の数には、数えるために開いた接続を含めない。テストは Linux のコンテナで動くので、Chromium の処理は /proc で数える。
// 入口のほかに処理を起動するものはこのテストに無いので、このテストの処理の子孫を、入口が起動した Chromium の処理として数える。
// 名前では数えないので、同時に動くほかのパッケージのテストの Chromium を数えず、ブラウザの名前が違っても数えられる。
func resources(t *testing.T, name string) (chromium, db, redis int) {
	t.Helper()
	proc := os.DirFS("/proc")
	entries, err := fs.ReadDir(proc, ".")
	if err != nil {
		t.Fatalf("処理の一覧を読めません: %v", err)
	}
	parents := make(map[int]int)
	for _, entry := range entries {
		pid, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}
		// 読むあいだに終わった処理は、読めないので数えない
		status, err := fs.ReadFile(proc, entry.Name()+"/status")
		if err != nil {
			continue
		}
		if ppid, alive := parseStatus(status); alive {
			parents[pid] = ppid
		}
	}
	self := os.Getpid()
	for pid := range parents {
		if descends(parents, pid, self) {
			chromium++
		}
	}
	if err := adminPool.QueryRow(t.Context(), `SELECT count(*) FROM pg_stat_activity WHERE datname = $1`, name).Scan(&db); err != nil {
		t.Fatalf("データベースへの接続の数を読めません: %v", err)
	}
	client := redisstore.New(redisstore.Options{Addr: net.JoinHostPort(redisHost, redisPort)})
	defer func() { _ = client.Close() }()
	info, err := client.Info(t.Context(), "clients").Result()
	if err != nil {
		t.Fatalf("Redis への接続の数を読めません: %v", err)
	}
	for line := range strings.SplitSeq(info, "\r\n") {
		if value, ok := strings.CutPrefix(line, "connected_clients:"); ok {
			if redis, err = strconv.Atoi(value); err != nil {
				t.Fatalf("Redis への接続の数 %q を読めません: %v", value, err)
			}
		}
	}
	return chromium, db, redis - 1
}

// parseStatus は、/proc/<pid>/status の中身から、親の処理の番号と、処理が終わっていないか(State が Z でないか)を読む。
func parseStatus(status []byte) (ppid int, alive bool) {
	alive = true
	for line := range strings.SplitSeq(string(status), "\n") {
		if value, ok := strings.CutPrefix(line, "PPid:"); ok {
			ppid, _ = strconv.Atoi(strings.TrimSpace(value))
		}
		if value, ok := strings.CutPrefix(line, "State:"); ok && strings.HasPrefix(strings.TrimSpace(value), "Z") {
			alive = false
		}
	}
	return ppid, alive
}

// descends は、処理 pid の親をたどって ancestor に着くかを返す。parents は、処理の番号から親の処理の番号への表である。
func descends(parents map[int]int, pid, ancestor int) bool {
	// 表の数より多くたどることはないので、親の番号が輪になっていても終わる
	for range len(parents) {
		ppid, ok := parents[pid]
		if !ok {
			return false
		}
		if ppid == ancestor {
			return true
		}
		pid = ppid
	}
	return false
}

// assertReleased は、入口が終わったあと、PDF の部品とデータベースと Redis の接続が10秒のうちに閉じられることを確かめる。
// Redis は、入口が閉じなくても、使われなくなったクライアントの接続を Go のメモリの片付けが閉じることがある。
// そのため、入口が作ったクライアント自身が閉じられたことも確かめる。
func assertReleased(t *testing.T, h *harness, name string) {
	t.Helper()
	if err := h.store.Ping(t.Context()).Err(); !errors.Is(err, redis.ErrClosed) {
		t.Errorf("入口が終わったあとの Redis のクライアントへの命令 = %v, want 閉じられている", err)
	}
	deadline := time.Now().Add(10 * time.Second)
	for {
		chromium, db, redis := resources(t, name)
		if chromium == 0 && db == 0 && redis == 0 {
			return
		}
		if time.Now().After(deadline) {
			t.Errorf("入口が終わったあとの Chromium の処理 = %d, データベースへの接続 = %d, Redis への接続 = %d, want どれも0", chromium, db, redis)
			return
		}
		time.Sleep(200 * time.Millisecond)
	}
}

// slowRequest は、ログインの要求のヘッダと本文の一部だけを送り、受け口が本文の残りを待つ状態にする。
// 返す関数は、本文の残りを送り、応答のステータスを返す。
func slowRequest(t *testing.T, addr string) (net.Conn, func() (int, error)) {
	t.Helper()
	body := `{"email":"a@example.com","password":"x"}`
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatalf("受け口につなげません: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	head := "POST /api/auth/login HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n" +
		"Content-Length: " + strconv.Itoa(len(body)) + "\r\n\r\n" + body[:5]
	if _, err := io.WriteString(conn, head); err != nil {
		t.Fatalf("要求を送れません: %v", err)
	}
	return conn, func() (int, error) {
		if _, err := io.WriteString(conn, body[5:]); err != nil {
			return 0, err
		}
		res, err := http.ReadResponse(bufio.NewReader(conn), nil)
		if err != nil {
			return 0, err
		}
		defer func() { _ = res.Body.Close() }()
		return res.StatusCode, nil
	}
}

// SIGTERM の代わりに context を終わらせると、新しい接続を断り、受けている要求が終わるのを待ってから0で終わることを確かめる。
func TestRun_GracefulShutdownWaits(t *testing.T) {
	name := newDatabase(t)
	h := newHarness(t, testEnv(t, name))
	stop, done := h.start(t)
	if chromium, db, redis := resources(t, name); chromium == 0 || db == 0 || redis == 0 {
		t.Fatalf("動いているあいだの Chromium の処理 = %d, データベースへの接続 = %d, Redis への接続 = %d, want どれも1つ以上", chromium, db, redis)
	}
	_, finish := slowRequest(t, h.addr)
	// 受け口が要求のヘッダを読み、本文の残りを待ち始めるまで待つ
	time.Sleep(500 * time.Millisecond)
	stop()

	select {
	case code := <-done:
		t.Fatalf("入口が、受けている要求の終わりを待たずに %d で終わりました", code)
	case <-time.After(time.Second):
	}
	if conn, err := net.DialTimeout("tcp", h.addr, time.Second); err == nil {
		_ = conn.Close()
		t.Error("止め始めたあとも、新しい接続を受けました")
	}
	status, err := finish()
	if err != nil || status != http.StatusNotImplemented {
		t.Errorf("受けていた要求の応答 = %d, %v, want 501", status, err)
	}
	select {
	case code := <-done:
		if code != 0 {
			t.Errorf("終了コード = %d, want 0", code)
		}
	case <-time.After(30 * time.Second):
		t.Fatal("受けていた要求が終わったあと、入口が30秒で終わりません")
	}
	if h.logs.find(t, "shutdown_started") == nil || h.logs.find(t, "stopped") == nil {
		t.Errorf("止めるときのログがありません: %s", h.logs.String())
	}
	assertReleased(t, h, name)

	t.Run("待つ時間を過ぎたら、接続を閉じて1で終わる", func(t *testing.T) {
		h := newHarness(t, testEnv(t, newDatabase(t)))
		h.deps.shutdownTimeout = 2 * time.Second
		stop, done := h.start(t)
		conn, _ := slowRequest(t, h.addr)
		time.Sleep(500 * time.Millisecond)
		began := time.Now()
		stop()
		select {
		case code := <-done:
			assertFailed(t, h, code, "shutdown_timeout", "受けている要求が 2s のあいだに終わりません")
			if elapsed := time.Since(began); elapsed < 2*time.Second || elapsed > 15*time.Second {
				t.Errorf("止めるまでの時間 = %s, want 2秒ほど", elapsed)
			}
		case <-time.After(30 * time.Second):
			t.Fatal("待つ時間を過ぎても、入口が終わりません")
		}
		if err := conn.SetReadDeadline(time.Now().Add(5 * time.Second)); err != nil {
			t.Fatalf("読む期限を置けません: %v", err)
		}
		if _, err := conn.Read(make([]byte, 1)); !errors.Is(err, io.EOF) {
			t.Errorf("待つ時間を過ぎた接続の読み込み = %v, want 閉じられている", err)
		}
	})
}

// 入口が、HTTP の受け口の共通の中間処理とデータベースをつないだ受け口を開くことを確かめる。
func TestRun_MiddlewareOrder(t *testing.T) {
	h := newHarness(t, testEnv(t, newDatabase(t)))
	stop, done := h.start(t)
	defer func() {
		stop()
		<-done
	}()
	base := "http://" + h.addr

	res, err := httpClient.Get(base + "/actuator/health")
	if err != nil {
		t.Fatalf("生きているかの確認を送れません: %v", err)
	}
	body, _ := io.ReadAll(res.Body)
	_ = res.Body.Close()
	if res.StatusCode != http.StatusOK || string(body) != `{"status":"UP"}` {
		t.Errorf("生きているかの確認 = %d %s, want 200 UP", res.StatusCode, body)
	}

	res, err = httpClient.Get(base + "/api/resumes")
	if err != nil {
		t.Fatalf("経歴書の一覧の要求を送れません: %v", err)
	}
	_ = res.Body.Close()
	var token string
	for _, cookie := range res.Cookies() {
		if cookie.Name == "XSRF-TOKEN" {
			token = cookie.Value
		}
	}
	if res.StatusCode != http.StatusNotImplemented || token == "" {
		t.Fatalf("経歴書の一覧 = %d, XSRF-TOKEN = %q, want 501 と新しいトークン", res.StatusCode, token)
	}

	post := func(withToken bool) int {
		req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, base+"/api/resumes", strings.NewReader(`{}`))
		if err != nil {
			t.Fatalf("要求を作れません: %v", err)
		}
		req.Header.Set("Content-Type", "application/json")
		if withToken {
			req.Header.Set("Cookie", "XSRF-TOKEN="+token)
			req.Header.Set("X-XSRF-TOKEN", token)
		}
		res, err := httpClient.Do(req)
		if err != nil {
			t.Fatalf("要求を送れません: %v", err)
		}
		_ = res.Body.Close()
		return res.StatusCode
	}
	if status := post(false); status != http.StatusForbidden {
		t.Errorf("トークンの無い POST = %d, want 403", status)
	}
	if status := post(true); status != http.StatusNotImplemented {
		t.Errorf("トークンのある POST = %d, want 501", status)
	}

	// 入口が、config の CORS の許す送り元を CORS の処理に渡すことを、API の説明画面の送り元からのプリフライトで確かめる
	req, err := http.NewRequestWithContext(t.Context(), http.MethodOptions, base+"/api/resumes", nil)
	if err != nil {
		t.Fatalf("要求を作れません: %v", err)
	}
	req.Header.Set("Origin", "http://localhost:8082")
	req.Header.Set("Access-Control-Request-Method", http.MethodPost)
	res, err = httpClient.Do(req)
	if err != nil {
		t.Fatalf("プリフライトを送れません: %v", err)
	}
	_ = res.Body.Close()
	if res.StatusCode != http.StatusOK || res.Header.Get("Access-Control-Allow-Origin") != "http://localhost:8082" {
		t.Errorf("説明画面の送り元からのプリフライト = %d, Access-Control-Allow-Origin = %q, want 200 と http://localhost:8082",
			res.StatusCode, res.Header.Get("Access-Control-Allow-Origin"))
	}

	var forbidden map[string]any
	for _, record := range h.logs.records(t) {
		if record["message"] == "request" && field(record, "http.response.status_code") == float64(403) {
			forbidden = record
		}
	}
	if forbidden == nil || field(forbidden, "http.request.method") != http.MethodPost {
		t.Errorf("偽の送信の検査で断った要求のログがありません: %s", h.logs.String())
	}
	if record := h.logs.find(t, "started"); field(record, "version") != "dev" || field(record, "service.environment") != "test" {
		t.Errorf("起動のログ = %v, want 版 dev と環境 test", record)
	}
}

// signalContext が、SIGTERM を受けたら終わる context を返すことを確かめる。
func TestSignalContext_SIGTERM(t *testing.T) {
	ctx, stop := signalContext()
	defer stop()
	if err := syscall.Kill(os.Getpid(), syscall.SIGTERM); err != nil {
		t.Fatalf("SIGTERM を送れません: %v", err)
	}
	select {
	case <-ctx.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("SIGTERM を受けても context が終わりません")
	}
}
