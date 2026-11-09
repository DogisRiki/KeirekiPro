// Package redisstore は、Redis への接続と、Java 版と同じ Lua のスクリプトを持つ。
// つなぎ先の値は引数で受け取り、設定の部品を読まない。
package redisstore

import (
	"crypto/tls"

	"github.com/redis/go-redis/v9"
)

// Options は、Redis のつなぎ先である。
type Options struct {
	// Addr は、ホストとポートを「ホスト:ポート」の形でつないだものである。クラスタの形では、クラスタの入口である。
	Addr     string
	Username string
	Password string
	// Cluster は、クラスタの形でつなぐかである。本番は true、dev と test は false にする。
	Cluster bool
	// TLS は、TLS でつなぐかである。本番は true、dev と test は false にする。
	TLS bool
}

// New は、Redis のクライアントを作る。この関数はつながない。最初の命令を送るときにつなぐ。
func New(opts Options) redis.UniversalClient {
	universal := &redis.UniversalOptions{
		Addrs:         []string{opts.Addr},
		Username:      opts.Username,
		Password:      opts.Password,
		IsClusterMode: opts.Cluster,
	}
	if opts.TLS {
		// ServerName は空にする。TLS の部品は、つなぐ先のホストの名前で証明書を確かめる。
		// クラスタの形では、入口と別のノードにもつなぐためである。
		universal.TLSConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	}
	return redis.NewUniversalClient(universal)
}

// consumeIfEqualSource は、Java 版の RedisEmailVerificationCurrentTokenStore の CONSUME_SCRIPT と同じ文字列である。
const consumeIfEqualSource = "if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) else return 0 end"

// ConsumeIfEqual は、キーに置いてある値が渡した値と同じときだけキーを消すスクリプトである。
// KEYS[1] にキー、ARGV[1] に比べる値を渡す。消せたら 1、消さなかったら 0 を返す。
var ConsumeIfEqual = redis.NewScript(consumeIfEqualSource)
