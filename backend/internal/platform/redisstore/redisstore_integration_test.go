package redisstore

import (
	"context"
	"fmt"
	"os"
	"testing"

	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)

// valkeyImage は、開発環境の redis のサービス(docker/redis/Dockerfile)と同じ版の Valkey である。
const valkeyImage = "valkey/valkey:8.0.12-alpine"

// testAddr は、テストの Valkey の「ホスト:ポート」である。
var testAddr string

// TestMain は、テストの全体で1つの Valkey のコンテナを動かす。
// Docker が無いときは、テストを飛ばさずに失敗させる。
func TestMain(m *testing.M) {
	os.Exit(runTests(m))
}

func runTests(m *testing.M) int {
	ctx := context.Background()
	container, err := testcontainers.Run(ctx, valkeyImage,
		testcontainers.WithExposedPorts("6379/tcp"),
		testcontainers.WithWaitStrategy(wait.ForListeningPort("6379/tcp")),
	)
	defer func() {
		if err := testcontainers.TerminateContainer(container); err != nil {
			fmt.Fprintf(os.Stderr, "Valkey のコンテナを止められません: %v\n", err)
		}
	}()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Valkey のコンテナを動かせません: %v\n", err)
		return 1
	}
	testAddr, err = container.PortEndpoint(ctx, "6379/tcp", "")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Valkey のつなぎ先を読めません: %v\n", err)
		return 1
	}
	return m.Run()
}

// Java 版の RedisEmailVerificationCurrentTokenStore と同じ形で値を置き、同じスクリプトが同じ結果を返すことを確かめる。
// Java 版は、値を JSON の文字列(前後に " を付けた形)で置き、比べる値も同じ形で渡す。
func TestScripts_SameResultAsJava(t *testing.T) {
	client := New(Options{Addr: testAddr})
	t.Cleanup(func() { _ = client.Close() })
	ctx := t.Context()
	const key = "email-verification:current:user-1"

	tests := []struct {
		name       string
		stored     *string
		compare    string
		wantResult int64
		wantLeft   bool
	}{
		{name: "同じ値なら消して 1 を返す", stored: ptr(`"jti-1"`), compare: `"jti-1"`, wantResult: 1, wantLeft: false},
		{name: "違う値なら消さずに 0 を返す", stored: ptr(`"jti-1"`), compare: `"jti-2"`, wantResult: 0, wantLeft: true},
		{name: "キーが無ければ 0 を返す", stored: nil, compare: `"jti-1"`, wantResult: 0, wantLeft: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := client.Del(ctx, key).Err(); err != nil {
				t.Fatalf("キーを消せません: %v", err)
			}
			if tt.stored != nil {
				if err := client.Set(ctx, key, *tt.stored, 0).Err(); err != nil {
					t.Fatalf("値を置けません: %v", err)
				}
			}
			got, err := ConsumeIfEqual.Run(ctx, client, []string{key}, tt.compare).Int64()
			if err != nil {
				t.Fatalf("スクリプトを動かせません: %v", err)
			}
			if got != tt.wantResult {
				t.Errorf("スクリプトの結果 = %d, want %d", got, tt.wantResult)
			}
			left, err := client.Exists(ctx, key).Result()
			if err != nil {
				t.Fatalf("キーがあるかを確かめられません: %v", err)
			}
			if (left == 1) != tt.wantLeft {
				t.Errorf("キーが残っているか = %t, want %t", left == 1, tt.wantLeft)
			}
		})
	}
}

func ptr(s string) *string { return &s }
