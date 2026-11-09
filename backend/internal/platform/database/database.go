// Package database は、PostgreSQL への pgx の接続の束を作る。
// つなぎ先の値は引数で受け取り、設定の部品を読まない。
package database

import (
	"context"
	"fmt"
	"net"
	"net/url"
	"strconv"

	"github.com/jackc/pgx/v5/pgxpool"
)

// MaxConns は、接続の束の接続の最大である。Java 版の HikariCP の既定の10と同じにする。
const MaxConns = 10

// TimeZone は、接続ごとに設定する時間帯である。日時を日本の時刻で読み書きするためである。
const TimeZone = "Asia/Tokyo"

// Options は、データベースのつなぎ先である。
type Options struct {
	Host     string
	Port     int
	Database string
	User     string
	Password string
}

// Open は、接続の束を作り、1回つないで確かめてから返す。
// 誤りには、パスワードを書かない。
func Open(ctx context.Context, opts Options) (*pgxpool.Pool, error) {
	// sslmode は、Java 版の PostgreSQL の JDBC ドライバの既定と同じ prefer にする。
	connURL := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(opts.User, opts.Password),
		Host:     net.JoinHostPort(opts.Host, strconv.Itoa(opts.Port)),
		Path:     "/" + opts.Database,
		RawQuery: "sslmode=prefer",
	}
	config, err := pgxpool.ParseConfig(connURL.String())
	if err != nil {
		// 接続の文字列にはパスワードが入るので、誤りの中身を返さない。
		return nil, fmt.Errorf("database: %s:%d/%s への接続の設定を作れません", opts.Host, opts.Port, opts.Database)
	}
	config.MaxConns = MaxConns
	config.ConnConfig.RuntimeParams["timezone"] = TimeZone

	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("database: 接続の束を作れません: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("database: %s:%d/%s につなげません: %w", opts.Host, opts.Port, opts.Database, err)
	}
	return pool, nil
}
