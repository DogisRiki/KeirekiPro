//go:build compat

package harness

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/redis/go-redis/v9"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

// postgresImage と valkeyImage は、開発環境の db と redis のサービスと同じ版である。
const (
	postgresImage = "postgres:17.11-alpine"
	valkeyImage   = "valkey/valkey:8.0.12-alpine"
)

// データベース: 表の形を適用したデータベースのすべての表を読み、表の形の履歴は読まないことを確かめる。
func TestDumpDatabase_ReadsAllTablesButHistory(t *testing.T) {
	ctx := t.Context()
	container, err := postgres.Run(ctx, postgresImage,
		postgres.WithDatabase("keireki_pro"),
		postgres.WithUsername("postgres"),
		postgres.WithPassword("postgres"),
		postgres.BasicWaitStrategies(),
	)
	t.Cleanup(func() {
		if err := testcontainers.TerminateContainer(container); err != nil {
			t.Errorf("Postgres のコンテナを止められません: %v", err)
		}
	})
	if err != nil {
		t.Fatalf("Postgres のコンテナを動かせません: %v", err)
	}
	conn, err := container.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatalf("つなぎ先を読めません: %v", err)
	}
	if _, err := ApplyMigrations(ctx, conn); err != nil {
		t.Fatalf("ApplyMigrations: %v", err)
	}
	db, err := pgx.Connect(ctx, conn)
	if err != nil {
		t.Fatalf("つなげません: %v", err)
	}
	t.Cleanup(func() { _ = db.Close(context.Background()) })
	const user = "11111111-1111-4111-8111-111111111111"
	for _, sql := range []string{
		`INSERT INTO users (id, email, created_at, updated_at) VALUES ('` + user + `', 'taro@example.com', '2026-11-09 10:00:00.123456', '2026-11-09 10:00:00')`,
		`INSERT INTO user_token_versions (user_id, token_version, updated_at) VALUES ('` + user + `', 3, '2026-11-09 10:00:00')`,
		`CREATE TABLE "Odd ""Name""" (v int)`,
		`INSERT INTO "Odd ""Name""" VALUES (1), (2)`,
	} {
		if _, err := db.Exec(ctx, sql); err != nil {
			t.Fatalf("%s: %v", sql, err)
		}
	}

	snapshot, err := DumpDatabase(ctx, conn)
	if err != nil {
		t.Fatalf("DumpDatabase: %v", err)
	}
	if _, ok := snapshot[historyTable]; ok {
		t.Errorf("%s を読みました", historyTable)
	}
	for _, table := range []string{"users", "resumes", "user_token_versions", "tech_stack_mst"} {
		if _, ok := snapshot[table]; !ok {
			t.Errorf("表 %s がありません(読んだ表: %d 個)", table, len(snapshot))
		}
	}
	if rows := snapshot["resumes"]; rows == nil || len(rows) != 0 {
		t.Errorf("空の表 resumes = %#v, want 空の並び", rows)
	}
	users := snapshot["users"]
	if len(users) != 1 {
		t.Fatalf("users = %+v", users)
	}
	want := map[string]any{
		"id": user, "email": "taro@example.com", "password": nil, "username": nil, "profile_image": nil,
		"two_factor_auth_enabled": false, "email_verified_at": nil, "pending_email": nil,
		"created_at": "2026-11-09T10:00:00.123456", "updated_at": "2026-11-09T10:00:00",
	}
	if canonicalJSON(users[0]) != canonicalJSON(want) {
		t.Errorf("users の行 = %s, want %s", canonicalJSON(users[0]), canonicalJSON(want))
	}
	if v := snapshot["user_token_versions"][0]["token_version"]; v != json.Number("3") {
		t.Errorf("token_version = %#v, want json.Number(\"3\")", v)
	}
	if rows := snapshot[`Odd "Name"`]; len(rows) != 2 {
		t.Errorf("名前に引用符のある表の行 = %+v", rows)
	}

	if _, err := DumpDatabase(ctx, "postgres://postgres:postgres@127.0.0.1:1/none?sslmode=disable&connect_timeout=1"); err == nil {
		t.Error("つなげないデータベースで誤りになりません")
	}
	if _, err := DumpDatabase(ctx, "::not a connection string"); err == nil {
		t.Error("読めない接続の文字で誤りになりません")
	}
}

// Redis: 型ごとの値と、残りの有効な時間を読むことを確かめる。
func TestDumpRedis_ReadsTypesAndTTL(t *testing.T) {
	ctx := t.Context()
	container, err := testcontainers.Run(ctx, valkeyImage,
		testcontainers.WithExposedPorts("6379/tcp"),
		testcontainers.WithWaitStrategy(wait.ForListeningPort("6379/tcp")),
	)
	t.Cleanup(func() {
		if err := testcontainers.TerminateContainer(container); err != nil {
			t.Errorf("Valkey のコンテナを止められません: %v", err)
		}
	})
	if err != nil {
		t.Fatalf("Valkey のコンテナを動かせません: %v", err)
	}
	addr, err := container.PortEndpoint(ctx, "6379/tcp", "")
	if err != nil {
		t.Fatalf("つなぎ先を読めません: %v", err)
	}
	client := redis.NewClient(&redis.Options{Addr: addr})
	t.Cleanup(func() { _ = client.Close() })

	pipe := client.TxPipeline()
	pipe.Set(ctx, "s:ttl", `"value"`, 900*time.Second)
	pipe.Set(ctx, "s:none", "1", 0)
	pipe.RPush(ctx, "l", "b", "a", "b")
	pipe.SAdd(ctx, "set", "b", "a", "c")
	pipe.HSet(ctx, "h", "z", "1", "a", "2")
	pipe.ZAdd(ctx, "z", redis.Z{Member: "two", Score: 2}, redis.Z{Member: "one", Score: 1.5})
	pipe.Expire(ctx, "set", time.Hour)
	if _, err := pipe.Exec(ctx); err != nil {
		t.Fatalf("値を置けません: %v", err)
	}

	entries, err := DumpRedis(ctx, client)
	if err != nil {
		t.Fatalf("DumpRedis: %v", err)
	}
	want := []RedisEntry{
		{Key: "h", Type: "hash", Value: `{"a":"2","z":"1"}`, TTL: -1},
		{Key: "l", Type: "list", Value: `["b","a","b"]`, TTL: -1},
		{Key: "s:none", Type: "string", Value: "1", TTL: -1},
		{Key: "s:ttl", Type: "string", Value: `"value"`, TTL: 900 * time.Second},
		{Key: "set", Type: "set", Value: `["a","b","c"]`, TTL: time.Hour},
		{Key: "z", Type: "zset", Value: `[["one",1.5],["two",2]]`, TTL: -1},
	}
	if len(entries) != len(want) {
		t.Fatalf("読んだキー = %+v", entries)
	}
	for i, w := range want {
		got := entries[i]
		if got.Key != w.Key || got.Type != w.Type || got.Value != w.Value {
			t.Errorf("キー[%d] = %+v, want %+v", i, got, w)
		}
		if w.TTL < 0 && got.TTL != -1 || w.TTL >= 0 && (got.TTL > w.TTL || got.TTL < w.TTL-5*time.Second) {
			t.Errorf("キー %s の有効な時間 = %v, want %v", w.Key, got.TTL, w.TTL)
		}
	}

	t.Run("読めない型は誤りにする", func(t *testing.T) {
		if err := client.XAdd(ctx, &redis.XAddArgs{Stream: "stream", Values: map[string]any{"k": "v"}}).Err(); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { client.Del(ctx, "stream") })
		if _, err := DumpRedis(ctx, client); err == nil || !strings.Contains(err.Error(), "stream") {
			t.Errorf("DumpRedis の誤り = %v", err)
		}
	})
	t.Run("つなげない Redis は誤りにする", func(t *testing.T) {
		closed := redis.NewClient(&redis.Options{Addr: "127.0.0.1:1", MaxRetries: -1, DialTimeout: time.Second})
		t.Cleanup(func() { _ = closed.Close() })
		if _, err := DumpRedis(ctx, closed); err == nil {
			t.Error("つなげないのに誤りになりません")
		}
	})
}
