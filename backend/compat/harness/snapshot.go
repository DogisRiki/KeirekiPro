//go:build compat

package harness

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

// historyTable は、比べない表である。表の形の履歴は、比べる検査が両方のデータベースに同じものを適用する。
const historyTable = "flyway_schema_history"

// DumpDatabase は、connString のデータベースの public のすべての表のすべての行を読む。flyway_schema_history は読まない。
// 行は to_jsonb で JSON にして読むので、日時は ISO 8601 の文字、bytea は \x で始まる16進の文字になる。
func DumpDatabase(ctx context.Context, connString string) (DBSnapshot, error) {
	pool, err := pgxpool.New(ctx, connString)
	if err != nil {
		return nil, fmt.Errorf("harness: データベースにつなげません: %w", err)
	}
	defer pool.Close()

	rows, err := pool.Query(ctx, `SELECT table_name FROM information_schema.tables
		WHERE table_schema = 'public' AND table_type = 'BASE TABLE' AND table_name <> $1 ORDER BY table_name`, historyTable)
	if err != nil {
		return nil, fmt.Errorf("harness: 表の一覧を読めません: %w", err)
	}
	tables, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return nil, fmt.Errorf("harness: 表の一覧を読めません: %w", err)
	}

	snapshot := DBSnapshot{}
	for _, table := range tables {
		ident := pgx.Identifier{"public", table}.Sanitize()
		rows, err := pool.Query(ctx, "SELECT to_jsonb(t)::text FROM "+ident+" AS t")
		if err != nil {
			return nil, fmt.Errorf("harness: 表 %s を読めません: %w", table, err)
		}
		texts, err := pgx.CollectRows(rows, pgx.RowTo[string])
		if err != nil {
			return nil, fmt.Errorf("harness: 表 %s を読めません: %w", table, err)
		}
		records := make([]map[string]any, 0, len(texts))
		for _, text := range texts {
			dec := json.NewDecoder(bytes.NewReader([]byte(text)))
			dec.UseNumber()
			var record map[string]any
			if err := dec.Decode(&record); err != nil {
				return nil, fmt.Errorf("harness: 表 %s の行を読めません: %w", table, err)
			}
			records = append(records, record)
		}
		snapshot[table] = records
	}
	return snapshot, nil
}

// DumpRedis は、Redis のすべてのキーの型と値と残りの有効な時間を読む。値は型ごとに次の文字の形にする。
//   - string: 値のまま
//   - list: 並びの順の JSON の配列
//   - set: 並べ替えた JSON の配列
//   - hash: 項目の名前の順の JSON のオブジェクト
//   - zset: 点数の順の、[メンバー, 点数] の JSON の配列
//
// 読んでいる間に消えたキーは返さない。
func DumpRedis(ctx context.Context, client *redis.Client) ([]RedisEntry, error) {
	var keys []string
	iter := client.Scan(ctx, 0, "*", 1000).Iterator()
	for iter.Next(ctx) {
		keys = append(keys, iter.Val())
	}
	if err := iter.Err(); err != nil {
		return nil, fmt.Errorf("harness: Redis のキーを読めません: %w", err)
	}
	slices.Sort(keys)
	keys = slices.Compact(keys)

	entries := make([]RedisEntry, 0, len(keys))
	for _, key := range keys {
		entry, ok, err := readRedisEntry(ctx, client, key)
		if err != nil {
			return nil, err
		}
		if ok {
			entries = append(entries, entry)
		}
	}
	return entries, nil
}

func readRedisEntry(ctx context.Context, client *redis.Client, key string) (RedisEntry, bool, error) {
	typ, err := client.Type(ctx, key).Result()
	if err != nil {
		return RedisEntry{}, false, fmt.Errorf("harness: Redis のキー %s の型を読めません: %w", key, err)
	}
	var value string
	switch typ {
	case "none":
		return RedisEntry{}, false, nil
	case "string":
		value, err = client.Get(ctx, key).Result()
	case "list":
		value, err = jsonResult(client.LRange(ctx, key, 0, -1).Result())
	case "set":
		var members []string
		members, err = client.SMembers(ctx, key).Result()
		slices.Sort(members)
		value = canonicalJSON(members)
	case "hash":
		value, err = jsonResult(client.HGetAll(ctx, key).Result())
	case "zset":
		var zs []redis.Z
		zs, err = client.ZRangeWithScores(ctx, key, 0, -1).Result()
		pairs := make([][]any, len(zs))
		for i, z := range zs {
			pairs[i] = []any{z.Member, z.Score}
		}
		value = canonicalJSON(pairs)
	default:
		return RedisEntry{}, false, fmt.Errorf("harness: Redis のキー %s の型 %s は読めません", key, typ)
	}
	if errors.Is(err, redis.Nil) {
		return RedisEntry{}, false, nil
	}
	if err != nil {
		return RedisEntry{}, false, fmt.Errorf("harness: Redis のキー %s の値を読めません: %w", key, err)
	}
	ttl, err := client.PTTL(ctx, key).Result()
	if err != nil {
		return RedisEntry{}, false, fmt.Errorf("harness: Redis のキー %s の有効な時間を読めません: %w", key, err)
	}
	if ttl == -2*time.Nanosecond || ttl == -2*time.Millisecond {
		return RedisEntry{}, false, nil
	}
	if ttl < 0 {
		ttl = -1
	}
	return RedisEntry{Key: key, Type: typ, Value: value, TTL: ttl}, true, nil
}

func jsonResult[T any](v T, err error) (string, error) {
	if err != nil {
		return "", err
	}
	return canonicalJSON(v), nil
}
