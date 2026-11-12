//go:build compat

package harness

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeoidc"
)

// readPEMCert は、PEM のファイルの最初の証明書を読む。
func readPEMCert(t *testing.T, file string) *x509.Certificate {
	t.Helper()
	data, err := os.ReadFile(filepath.Clean(file))
	if err != nil {
		t.Fatal(err)
	}
	block, _ := pem.Decode(data)
	if block == nil || block.Type != "CERTIFICATE" {
		t.Fatalf("%s に PEM の証明書がありません", file)
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	return cert
}

// rootsOf は、a の認証局の証明書だけを信頼する束を返す。
func rootsOf(t *testing.T, a *TLSAlias) *x509.CertPool {
	t.Helper()
	pool := x509.NewCertPool()
	pool.AddCert(readPEMCert(t, a.CACertFile))
	return pool
}

func TestTLSAlias_CertValidForAPIGitHub(t *testing.T) {
	a, err := NewTLSAlias(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	ca := readPEMCert(t, a.CACertFile)
	if !ca.IsCA || ca.KeyUsage&x509.KeyUsageCertSign == 0 {
		t.Errorf("認証局の証明書 IsCA = %v、KeyUsage = %v, want 認証局として証明書に署名できる", ca.IsCA, ca.KeyUsage)
	}
	leaf := readPEMCert(t, a.CertFile)
	if leaf.IsCA {
		t.Error("api.github.com の証明書が認証局になっています")
	}
	opts := x509.VerifyOptions{DNSName: GitHubAPIHost, Roots: rootsOf(t, a), KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
	if _, err := leaf.Verify(opts); err != nil {
		t.Errorf("api.github.com の証明書を認証局で確かめられません: %v", err)
	}
	opts.DNSName = "github.com"
	if _, err := leaf.Verify(opts); err == nil {
		t.Error("api.github.com の証明書が github.com にも通りました")
	}
	// 検査のたびに認証局を作るので、別の検査の認証局では確かめられない
	other, err := NewTLSAlias(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	opts.DNSName = GitHubAPIHost
	opts.Roots = rootsOf(t, other)
	if _, err := leaf.Verify(opts); err == nil {
		t.Error("api.github.com の証明書が、別の検査の認証局でも通りました")
	}

	// 証明書と鍵で TLS を受け、認証局だけを信頼するクライアントが api.github.com としてつなげる
	pair, err := tls.LoadX509KeyPair(a.CertFile, a.KeyFile)
	if err != nil {
		t.Fatalf("証明書と鍵の組を読めません: %v", err)
	}
	ln, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{pair}})
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = ln.Close() }()
	go func() {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		_ = conn.(*tls.Conn).Handshake()
		_ = conn.Close()
	}()
	conn, err := tls.Dial("tcp", ln.Addr().String(), &tls.Config{MinVersion: tls.VersionTLS12, RootCAs: rootsOf(t, a), ServerName: GitHubAPIHost})
	if err != nil {
		t.Fatalf("api.github.com として TLS でつなげません: %v", err)
	}
	_ = conn.Close()
}

func TestTLSAlias_FilesStayInWorkDir(t *testing.T) {
	dir := t.TempDir()
	a, err := NewTLSAlias(dir)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, file := range []string{a.CACertFile, a.CertFile, a.KeyFile} {
		if filepath.Dir(file) != dir {
			t.Errorf("ファイル %s が、作業用のフォルダ %s の外にあります", file, dir)
		}
		info, err := os.Stat(file)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != 0o600 {
			t.Errorf("ファイル %s の権限 = %v, want 0600", file, info.Mode().Perm())
		}
		names = append(names, filepath.Base(file))
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, e := range entries {
		got = append(got, e.Name())
	}
	slices.Sort(names)
	if !slices.Equal(got, names) {
		t.Errorf("作業用のフォルダのファイル = %v, want %v", got, names)
	}
	if a.TrustStoreFile != "" {
		t.Errorf("信頼の束 = %q, want 作る前は空", a.TrustStoreFile)
	}
	other, err := NewTLSAlias(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if a.TrustStorePassword == "" || a.TrustStorePassword == other.TrustStorePassword {
		t.Errorf("信頼の束のパスワード = %q と %q, want 検査ごとに違う値", a.TrustStorePassword, other.TrustStorePassword)
	}

	t.Run("検査の環境を片付けると作業用のフォルダが消える", func(t *testing.T) {
		env, err := NewEnv(t.Context())
		if err != nil {
			t.Fatal(err)
		}
		work := env.WorkDir()
		if info, err := os.Stat(work); err != nil || !info.IsDir() {
			t.Fatalf("作業用のフォルダ %s がありません: %v", work, err)
		}
		if _, err := NewTLSAlias(work); err != nil {
			t.Fatal(err)
		}
		if err := env.Terminate(context.Background()); err != nil {
			t.Fatal(err)
		}
		if _, err := os.Stat(work); !os.IsNotExist(err) {
			t.Errorf("片付けたあとの作業用のフォルダ %s: %v, want 無い", work, err)
		}
	})
}

// javaRuntimeImage は、Java 版のイメージの実行の工程の元のイメージ(keytool を含む JRE)を、Dockerfile.prod の最後の FROM から読む。
// Java 版のイメージを組み立てると数分かかるので、keytool を動かす確かめには、元のイメージを使う。
func javaRuntimeImage(t *testing.T) string {
	t.Helper()
	root, err := RepoRoot()
	if err != nil {
		t.Fatal(err)
	}
	f, err := os.Open(filepath.Clean(filepath.Join(root, "docker", "backend", "Dockerfile.prod")))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = f.Close() }()
	image := ""
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if fields := strings.Fields(sc.Text()); len(fields) >= 2 && fields[0] == "FROM" {
			image = fields[1]
		}
	}
	if err := sc.Err(); err != nil || image == "" {
		t.Fatalf("Java 版の Dockerfile.prod の FROM を読めません: %v", err)
	}
	return image
}

// fingerprint は、証明書の SHA-256 を keytool の書き方(大文字の16進数をコロンでつなぐ)で返す。
func fingerprint(cert *x509.Certificate) string {
	sum := sha256.Sum256(cert.Raw)
	parts := make([]string, len(sum))
	for i, b := range sum {
		parts[i] = fmt.Sprintf("%02X", b)
	}
	return strings.Join(parts, ":")
}

// containerLogs は、コンテナのログを読む。
func containerLogs(t *testing.T, c *Container) string {
	t.Helper()
	logs, err := c.Logs(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = logs.Close() }()
	text, err := io.ReadAll(logs)
	if err != nil {
		t.Fatal(err)
	}
	return string(text)
}

func TestTLSAlias_TrustStoreHoldsCA(t *testing.T) {
	ctx := t.Context()
	image := javaRuntimeImage(t)
	env, err := NewEnv(ctx)
	if err != nil {
		t.Fatal(err)
	}
	env.Cleanup(t)
	a, err := NewTLSAlias(env.WorkDir())
	if err != nil {
		t.Fatal(err)
	}
	if err := a.BuildTrustStore(ctx, env, image); err != nil {
		t.Fatal(err)
	}
	if filepath.Dir(a.TrustStoreFile) != env.WorkDir() {
		t.Errorf("信頼の束 %s が、作業用のフォルダ %s の外にあります", a.TrustStoreFile, env.WorkDir())
	}
	info, err := os.Stat(a.TrustStoreFile)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("信頼の束の権限 = %v, want 0600", info.Mode().Perm())
	}
	// keytool は1回だけ動かす
	env.mu.Lock()
	before := len(env.containers)
	env.mu.Unlock()
	if err := a.BuildTrustStore(ctx, env, image); err != nil {
		t.Fatal(err)
	}
	env.mu.Lock()
	after := len(env.containers)
	env.mu.Unlock()
	if after != before {
		t.Errorf("2回目の BuildTrustStore がコンテナを %d 個起動しました, want 0 個", after-before)
	}

	// 作った信頼の束を、パスワードで開き、認証局の証明書が信頼する証明書として入っていることを keytool で確かめる
	c, err := env.Start(ctx, ContainerSpec{
		Name:       "keytool-list",
		Image:      image,
		Entrypoint: []string{"keytool"},
		Cmd:        []string{"-list", "-v", "-storetype", "PKCS12", "-keystore", "/check/truststore.p12", "-storepass", a.TrustStorePassword},
		Files:      []testcontainers.ContainerFile{{HostFilePath: a.TrustStoreFile, ContainerFilePath: "/check/truststore.p12", FileMode: 0o644}},
		WaitingFor: wait.ForExit(),
	})
	if err != nil {
		t.Fatal(err)
	}
	out := containerLogs(t, c)
	if !strings.Contains(out, "trustedCertEntry") || !strings.Contains(out, fingerprint(readPEMCert(t, a.CACertFile))) {
		t.Errorf("信頼の束の中身 = %q, want 認証局の証明書の信頼する項目", out)
	}

	t.Run("keytool が失敗すれば誤りを返す", func(t *testing.T) {
		bad, err := NewTLSAlias(t.TempDir())
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(bad.CACertFile, []byte("証明書ではない"), 0o600); err != nil {
			t.Fatal(err)
		}
		err = bad.BuildTrustStore(ctx, env, image)
		// 終了コードで失敗を見つけ、keytool が出した誤りの文を添える
		if err == nil || !strings.Contains(err.Error(), "終了コード") || !strings.Contains(err.Error(), "keytool error") {
			t.Errorf("BuildTrustStore = %v, want keytool の終了コードと誤りの文", err)
		}
		if bad.TrustStoreFile != "" {
			t.Errorf("失敗したあとの信頼の束 = %q, want 空", bad.TrustStoreFile)
		}
	})
}

func TestTLSAlias_FakeOIDCServesAPIGitHub(t *testing.T) {
	ctx := t.Context()
	root, err := RepoRoot()
	if err != nil {
		t.Fatal(err)
	}
	var buildLog bytes.Buffer
	images, err := BuildImages(ctx, root, &buildLog, ImageFakeOIDC)
	t.Cleanup(func() {
		if err := images.Remove(context.Background()); err != nil {
			t.Errorf("組み立てたイメージを消せません: %v", err)
		}
	})
	if err != nil {
		t.Fatalf("BuildImages: %v\n%s", err, buildLog.String())
	}
	env, err := NewEnv(ctx)
	if err != nil {
		t.Fatal(err)
	}
	env.Cleanup(t)
	a, err := NewTLSAlias(env.WorkDir())
	if err != nil {
		t.Fatal(err)
	}
	spec := fakeOIDCSpec(images[ImageFakeOIDC], a)
	if !slices.Contains(spec.Aliases, GitHubAPIHost) {
		t.Errorf("fakeoidc の別名 = %v, want %s を含む", spec.Aliases, GitHubAPIHost)
	}
	// テストの処理から TLS の受け口へつなぐために、ポート 443 も外に出す
	spec.ExposedPorts = append(spec.ExposedPorts, fakeoidc.TLSPort+"/tcp")
	c, err := env.Start(ctx, spec)
	if err != nil {
		t.Fatal(err)
	}
	endpoint, err := c.PortEndpoint(ctx, fakeoidc.TLSPort+"/tcp", "https")
	if err != nil {
		t.Fatal(err)
	}
	client := &http.Client{
		Timeout: RequestTimeout,
		Transport: &http.Transport{TLSClientConfig: &tls.Config{
			MinVersion: tls.VersionTLS12, RootCAs: rootsOf(t, a), ServerName: GitHubAPIHost,
		}},
	}
	// fakeoidc は、ポート 8080 で答え始めたあとに TLS を受け始めることがあるので、少し待つ
	deadline := time.Now().Add(10 * time.Second)
	for {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint+"/not-github", nil)
		if err != nil {
			t.Fatal(err)
		}
		resp, err := client.Do(req)
		if err == nil {
			_ = resp.Body.Close()
			if resp.StatusCode != http.StatusNotImplemented {
				t.Errorf("api.github.com の /not-github の応答 = %d, want 501", resp.StatusCode)
			}
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("コンテナの fakeoidc に、api.github.com として TLS でつなげません: %v\n%s", err, containerLogs(t, c))
		}
		time.Sleep(200 * time.Millisecond)
	}
}
