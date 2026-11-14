package users

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/awsclient"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/migrate"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// postgresImage は、開発環境の db のサービス(docker/db/Dockerfile)と同じ版の Postgres である。
const postgresImage = "postgres:17.11-alpine"

// valkeyImage は、開発環境の redis のサービス(docker/redis/Dockerfile)と同じ版の Valkey である。
const valkeyImage = "valkey/valkey:8.0.12-alpine"

// fakeAWSPort は、偽の AWS(backend/compat/fakeaws)が受けるポートである。
// 偽の AWS のパッケージはビルドタグ compat を付けているので、ここからは読めない。値を写して書く。
const fakeAWSPort = "4566/tcp"

// testRegion は、テストの S3 のクライアントのリージョンである。開発環境の設定と同じ値である。
const testRegion = "ap-northeast-1"

// testBucket は、テストの画像の置き場所である。開発環境の設定と同じ名前である。
const testBucket = "keirekipro-storage"

var (
	// testPool は、テストの Postgres への接続の束である。TestMain が、Java 版の Flyway と同じ表を作ってから渡す。
	testPool *pgxpool.Pool
	// testRedisAddr は、テストの Valkey の「ホスト:ポート」である。
	testRedisAddr string
	// testAWSEndpoint は、テストの偽の AWS の URL である(例: http://localhost:32768)。
	testAWSEndpoint string
)

// TestMain は、テストの全体で1つの Postgres のコンテナと1つの Valkey のコンテナと1つの偽の AWS のコンテナを動かし、
// backend.Migrations() のマイグレーションを流して表を作る。
// 偽の AWS のイメージは、backend/compat/fakeaws/Dockerfile から組み立てる。
// Docker が無いときは、テストを飛ばさずに失敗させる。
func TestMain(m *testing.M) {
	os.Exit(runTests(m))
}

func runTests(m *testing.M) int {
	ctx := context.Background()

	pg, err := postgres.Run(ctx, postgresImage,
		postgres.WithDatabase("keireki_pro"),
		postgres.WithUsername("postgres"),
		postgres.WithPassword("postgres"),
		postgres.BasicWaitStrategies(),
	)
	defer terminate("Postgres", pg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres のコンテナを動かせません: %v\n", err)
		return 1
	}
	opts, err := databaseOptions(ctx, pg)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	testPool, err = database.Open(ctx, opts)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Postgres につなげません: %v\n", err)
		return 1
	}
	defer testPool.Close()
	files, err := backend.Migrations()
	if err != nil {
		fmt.Fprintf(os.Stderr, "マイグレーションのファイルを読めません: %v\n", err)
		return 1
	}
	if _, err := migrate.Run(ctx, testPool, files, migrate.Apply); err != nil {
		fmt.Fprintf(os.Stderr, "マイグレーションを流せません: %v\n", err)
		return 1
	}

	valkey, err := testcontainers.Run(ctx, valkeyImage,
		testcontainers.WithExposedPorts("6379/tcp"),
		testcontainers.WithWaitStrategy(wait.ForListeningPort("6379/tcp")),
	)
	defer terminate("Valkey", valkey)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Valkey のコンテナを動かせません: %v\n", err)
		return 1
	}
	testRedisAddr, err = valkey.PortEndpoint(ctx, "6379/tcp", "")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Valkey のつなぎ先を読めません: %v\n", err)
		return 1
	}

	// 組み立ての文脈は backend のフォルダである(テストはパッケージのフォルダ internal/users で動く)。
	// 文脈の .dockerignore が、build などの要らないファイルを除く。
	fake, err := testcontainers.Run(ctx, "",
		testcontainers.WithDockerfile(testcontainers.FromDockerfile{
			Context:    "../..",
			Dockerfile: "compat/fakeaws/Dockerfile",
		}),
		testcontainers.WithExposedPorts(fakeAWSPort),
		testcontainers.WithWaitStrategy(wait.ForHTTP("/_compat/healthz").WithPort(fakeAWSPort)),
	)
	defer terminate("偽の AWS", fake)
	if err != nil {
		fmt.Fprintf(os.Stderr, "偽の AWS のコンテナを動かせません: %v\n", err)
		return 1
	}
	testAWSEndpoint, err = fake.PortEndpoint(ctx, fakeAWSPort, "http")
	if err != nil {
		fmt.Fprintf(os.Stderr, "偽の AWS のつなぎ先を読めません: %v\n", err)
		return 1
	}
	return m.Run()
}

// databaseOptions は、Postgres のコンテナのつなぎ先を、database.Open に渡す形にする。
func databaseOptions(ctx context.Context, pg *postgres.PostgresContainer) (database.Options, error) {
	endpoint, err := pg.PortEndpoint(ctx, "5432/tcp", "")
	if err != nil {
		return database.Options{}, fmt.Errorf("テストの Postgres のつなぎ先を読めません: %w", err)
	}
	host, portText, err := net.SplitHostPort(endpoint)
	if err != nil {
		return database.Options{}, fmt.Errorf("テストの Postgres のつなぎ先 %s を読めません: %w", endpoint, err)
	}
	port, err := strconv.Atoi(portText)
	if err != nil {
		return database.Options{}, fmt.Errorf("テストの Postgres のポート %s を読めません: %w", portText, err)
	}
	return database.Options{Host: host, Port: port, Database: "keireki_pro", User: "postgres", Password: "postgres"}, nil
}

// terminate は、テストのコンテナを止める。
func terminate(name string, c testcontainers.Container) {
	if err := testcontainers.TerminateContainer(c); err != nil {
		fmt.Fprintf(os.Stderr, "%s のコンテナを止められません: %v\n", name, err)
	}
}

// newTestS3 は、テストの偽の AWS につなぐ S3 のクライアントを、本番と同じ awsclient.New で作る。
func newTestS3(t *testing.T) *s3.Client {
	t.Helper()
	clients, err := awsclient.New(t.Context(), awsclient.Options{Region: testRegion, Endpoint: testAWSEndpoint})
	if err != nil {
		t.Fatalf("S3 のクライアントを作れません: %v", err)
	}
	return clients.S3
}

// TestIntegrationSetup は、TestMain が、利用者の処理の結合テストの土台を用意してあることを確かめる。
func TestIntegrationSetup(t *testing.T) {
	t.Run("退会で消す表と認証の表がある", func(t *testing.T) {
		for _, table := range []string{
			"users", "roles", "user_roles", "user_auth_providers", "user_token_versions",
			"resumes", "careers", "projects", "project_tech_stacks", "certifications",
			"portfolios", "sns_platforms", "self_promotions",
		} {
			var exists bool
			if err := testPool.QueryRow(t.Context(), "SELECT to_regclass($1) IS NOT NULL", "public."+table).Scan(&exists); err != nil {
				t.Fatalf("表 %s を調べられません: %v", table, err)
			}
			if !exists {
				t.Errorf("表 %s が無い", table)
			}
		}
	})

	t.Run("Valkey に書いて読める", func(t *testing.T) {
		client := redisstore.New(redisstore.Options{Addr: testRedisAddr})
		t.Cleanup(func() { _ = client.Close() })
		const key = "users-integration-setup"
		if err := client.Set(t.Context(), key, "ok", 0).Err(); err != nil {
			t.Fatalf("Valkey に書けません: %v", err)
		}
		t.Cleanup(func() { _ = client.Del(context.Background(), key).Err() })
		got, err := client.Get(t.Context(), key).Result()
		if err != nil {
			t.Fatalf("Valkey から読めません: %v", err)
		}
		if got != "ok" {
			t.Errorf("Valkey の値 = %q, want %q", got, "ok")
		}
	})

	t.Run("偽の AWS に名前が / で始まる画像を置いて読める", func(t *testing.T) {
		client := newTestS3(t)
		// Java 版の画像の名前は / で始まるので、URL のパスに // が入る
		const key = "/profile/image/6f1c2a3b-0000-4000-8000-000000000001.png"
		body := []byte("\x89PNG\r\n\x1a\nsetup")
		if _, err := client.PutObject(t.Context(), &s3.PutObjectInput{
			Bucket:      aws.String(testBucket),
			Key:         aws.String(key),
			Body:        bytes.NewReader(body),
			ContentType: aws.String("image/png"),
		}); err != nil {
			t.Fatalf("画像を置けません: %v", err)
		}
		t.Cleanup(func() {
			_, _ = client.DeleteObject(context.Background(), &s3.DeleteObjectInput{Bucket: aws.String(testBucket), Key: aws.String(key)})
		})
		out, err := client.GetObject(t.Context(), &s3.GetObjectInput{Bucket: aws.String(testBucket), Key: aws.String(key)})
		if err != nil {
			t.Fatalf("画像を読めません: %v", err)
		}
		defer func() { _ = out.Body.Close() }()
		got, err := io.ReadAll(out.Body)
		if err != nil {
			t.Fatalf("画像の中身を読めません: %v", err)
		}
		if !bytes.Equal(got, body) {
			t.Errorf("読んだ画像 = %q, want %q", got, body)
		}
		if ct := aws.ToString(out.ContentType); ct != "image/png" {
			t.Errorf("Content-Type = %q, want %q", ct, "image/png")
		}
	})
}
