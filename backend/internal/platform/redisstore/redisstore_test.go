package redisstore

import (
	"crypto/tls"
	"testing"

	"github.com/redis/go-redis/v9"
)

// 本番の形では、クラスタの形と TLS と利用者の名前でつなぐクライアントを作ることを確かめる。
func TestNew_ProdUsesClusterAndTLS(t *testing.T) {
	client := New(Options{Addr: "cache.example.com:6379", Username: "app", Password: "pw", Cluster: true, TLS: true})
	t.Cleanup(func() { _ = client.Close() })

	cluster, ok := client.(*redis.ClusterClient)
	if !ok {
		t.Fatalf("クライアントの型 = %T, want *redis.ClusterClient", client)
	}
	opts := cluster.Options()
	if len(opts.Addrs) != 1 || opts.Addrs[0] != "cache.example.com:6379" {
		t.Errorf("入口 = %v, want [cache.example.com:6379]", opts.Addrs)
	}
	if opts.Username != "app" || opts.Password != "pw" {
		t.Errorf("利用者の名前とパスワード = (%q, %q), want (app, pw)", opts.Username, opts.Password)
	}
	if opts.TLSConfig == nil {
		t.Fatal("TLS の設定 = nil, want TLS でつなぐ設定")
	}
	if opts.TLSConfig.MinVersion != tls.VersionTLS12 {
		t.Errorf("TLS の最小の版 = %x, want TLS 1.2", opts.TLSConfig.MinVersion)
	}
}

// dev と test の形では、1台の形で、TLS を使わずにつなぐクライアントを作ることを確かめる。
func TestNew_DevUsesSingleNode(t *testing.T) {
	client := New(Options{Addr: "redis:6379", Password: "pw"})
	t.Cleanup(func() { _ = client.Close() })

	single, ok := client.(*redis.Client)
	if !ok {
		t.Fatalf("クライアントの型 = %T, want *redis.Client", client)
	}
	opts := single.Options()
	if opts.Addr != "redis:6379" || opts.Password != "pw" {
		t.Errorf("つなぎ先 = (%q, %q), want (redis:6379, pw)", opts.Addr, opts.Password)
	}
	if opts.TLSConfig != nil {
		t.Errorf("TLS の設定 = %+v, want nil", opts.TLSConfig)
	}
}
