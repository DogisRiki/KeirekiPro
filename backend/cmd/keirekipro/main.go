// Command keirekipro は、Go 版の backend の起動の入口である。
//
// 入口は、設定を読み、表の形の履歴を確かめ、データベースと Redis と AWS と PDF の部品をつなぎ、
// HTTP の受け口を 8080 で開く。業務の処理は持たない。
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/awsclient"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/logging"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/migrate"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/pdf"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// version は、動かしているイメージの版である。本番のイメージは、組み立てのときに -X main.version で git のコミットを入れる。
var version = "dev"

const (
	// serviceName は、ログの service.name に書く名前である。Java 版の spring.application.name と同じにする。
	serviceName = "keirekipro"
	// listenAddr は、HTTP の受け口を開く場所である。コンテナの外から届くように、すべての宛先で 8080 を開く。
	listenAddr = ":8080"
	// shutdownTimeout は、SIGTERM を受けてから、受けている要求が終わるのを待つ最大の時間である。
	// Java 版も止める手順の区切りごとに最大90秒待つので、同じ90秒にする。
	// ECS は、SIGTERM のあと stopTimeout の120秒でコンテナを強制的に止めるので、120秒より短くする。
	shutdownTimeout = 90 * time.Second
	// readHeaderTimeout は、要求のヘッダを読み終えるまでの最大の時間である。
	// ヘッダを少しずつ送って接続を持ち続ける要求で、受け口が埋まらないようにする。
	readHeaderTimeout = 20 * time.Second
)

// deps は、入口が使う外とのつなぎ方である。テストは、つなぎ方の一部を替えて、失敗する場合を確かめる。
type deps struct {
	// lookup は、環境変数を読む関数である。
	lookup config.Lookup
	// stdout は、ログを書く先である。
	stdout io.Writer
	// listen は、HTTP の受け口の接続を受ける口を開く。
	listen func() (net.Listener, error)
	// migrations は、マイグレーションのファイルを返す。
	migrations func() (fs.FS, error)
	// newRedis は、Redis のクライアントを作る。
	newRedis func(redisstore.Options) redis.UniversalClient
	// newAWS は、AWS のクライアントを作る。
	newAWS func(context.Context, awsclient.Options) (awsclient.Clients, error)
	// newPDF は、PDF を作る部品を作る。
	newPDF func(pdf.Options) (*pdf.Engine, error)
	// shutdownTimeout は、止めるときに、受けている要求が終わるのを待つ最大の時間である。
	shutdownTimeout time.Duration
}

func main() {
	os.Exit(start())
}

// start は、SIGTERM と割り込みで終わる context で、本当のつなぎ方を使って入口を動かす。
func start() int {
	ctx, stop := signalContext()
	defer stop()
	return run(ctx, deps{
		lookup: os.LookupEnv,
		stdout: os.Stdout,
		listen: func() (net.Listener, error) {
			var lc net.ListenConfig
			return lc.Listen(context.Background(), "tcp", listenAddr)
		},
		migrations:      backend.Migrations,
		newRedis:        redisstore.New,
		newAWS:          awsclient.New,
		newPDF:          pdf.New,
		shutdownTimeout: shutdownTimeout,
	})
}

// signalContext は、SIGTERM か割り込みを受けたら終わる context を返す。
func signalContext() (context.Context, context.CancelFunc) {
	return signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
}

// run は、部品をつないで HTTP の受け口を開き、ctx が終わるまで要求を受ける。
// ctx が終わったら、新しい接続を断り、受けている要求が終わるのを待ってから、部品を閉じて0を返す。
// 起動のどこかが失敗したときと、待つ時間を過ぎたときは、理由をログに書いて1を返す。
func run(ctx context.Context, d deps) int {
	logger := newLogger(d.stdout, "")
	cfg, err := config.Load(ctx, d.lookup)
	if err != nil {
		return fail(logger, "startup_failed", "設定を読めません", err)
	}
	logger = newLogger(d.stdout, string(cfg.Env))

	pool, err := database.Open(ctx, cfg.Database)
	if err != nil {
		return fail(logger, "startup_failed", "データベースにつなげません", err)
	}
	defer pool.Close()

	files, err := d.migrations()
	if err != nil {
		return fail(logger, "startup_failed", "マイグレーションのファイルを読めません", err)
	}
	// Java 版を削除するまでは、表の形は Java 版の Flyway が変える。Go 版は履歴を確かめるだけにする
	result, err := migrate.Run(ctx, pool, files, migrate.ValidateOnly)
	if err != nil {
		return fail(logger, "startup_failed", "表の形の履歴を確かめられません", err)
	}
	logger.Info("migration_validated",
		slog.Int("validated", len(result.Validated)), slog.Any("pending", result.Pending))

	store := d.newRedis(cfg.Redis)
	defer func() {
		if err := store.Close(); err != nil {
			logger.LogAttrs(context.Background(), slog.LevelWarn, "redis_close_failed", logging.ErrorAttr(err, nil))
		}
	}()
	if err := store.Ping(ctx).Err(); err != nil {
		return fail(logger, "startup_failed", "Redis につなげません", err)
	}

	// AWS のクライアントは、まとまりの spec が、機能のパッケージに渡す
	if _, err := d.newAWS(ctx, cfg.AWS); err != nil {
		return fail(logger, "startup_failed", "AWS のクライアントを作れません", err)
	}

	engine, err := d.newPDF(pdf.Options{Logger: logging.Named(logger, "pdf")})
	if err != nil {
		return fail(logger, "startup_failed", "PDF を作る部品を起動できません", err)
	}
	defer engine.Close()

	listener, err := d.listen()
	if err != nil {
		return fail(logger, "startup_failed", "HTTP の受け口を開けません", err)
	}
	server := &http.Server{
		Handler:           httpapi.New(httpapi.Options{Logger: logger, DB: pool, CORSAllowedOrigins: cfg.App.CORSAllowedOrigins}),
		ReadHeaderTimeout: readHeaderTimeout,
		ErrorLog:          slog.NewLogLogger(logging.Named(logger, "http").Handler(), slog.LevelWarn),
	}
	served := make(chan error, 1)
	go func() { served <- server.Serve(listener) }()
	logger.Info("started", slog.String("addr", listener.Addr().String()), slog.String("version", version))

	select {
	case err := <-served:
		return fail(logger, "serve_failed", "HTTP の受け口が止まりました", err)
	case <-ctx.Done():
	}

	logger.Info("shutdown_started")
	waitCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), d.shutdownTimeout)
	defer cancel()
	if err := server.Shutdown(waitCtx); err != nil {
		err = errors.Join(err, server.Close())
		return fail(logger, "shutdown_timeout", fmt.Sprintf("受けている要求が %s のあいだに終わりません", d.shutdownTimeout), err)
	}
	logger.Info("stopped")
	return 0
}

// newLogger は、標準出力に ECS の形のログを書くロガーを作る。
func newLogger(w io.Writer, env string) *slog.Logger {
	logger := logging.New(w, logging.Options{
		Service: logging.Service{Name: serviceName, Environment: env, Version: version},
	})
	return logging.Named(logger, "main")
}

// fail は、入口が終わる理由を、event の名前で ERROR のログに書き、終了コード1を返す。
func fail(logger *slog.Logger, event, reason string, err error) int {
	logger.LogAttrs(context.Background(), slog.LevelError, event,
		logging.ErrorAttr(fmt.Errorf("%s: %w", reason, err), nil))
	return 1
}
