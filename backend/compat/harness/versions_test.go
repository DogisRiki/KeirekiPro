//go:build compat

package harness

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/testcontainers/testcontainers-go"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeoidc"
)

// sample は、テストのつなぎ先の値を作る。
func sample(name string) string {
	return "compat-" + name
}

func sampleBacking() Backing {
	return Backing{
		DBHost: "postgres-java", DBPort: "5432", DBName: "keireki_pro", DBUser: sample("db-user"), DBPassword: sample("db-pass"),
		RedisHost: "redis-java", RedisPort: "6379", RedisPassword: sample("redis-pass"),
		JWTSecret:   sample("jwt"),
		AWSEndpoint: "http://fakeaws-java:4566",
		OIDCBaseURL: "http://fakeoidc:8080",
		Google:      fakeoidc.Client{ID: sample("google-id"), Secret: sample("google-value")},
		GitHub:      fakeoidc.Client{ID: sample("github-id"), Secret: sample("github-value")},
	}
}

// oidcURL は、sampleBacking の fakeoidc の URL に path を足す。
func oidcURL(path string) string {
	return "http://fakeoidc:8080" + path
}

func assertEnv(t *testing.T, got, want map[string]string) {
	t.Helper()
	if len(got) != len(want) {
		t.Errorf("環境変数の数 = %d, want %d: %v", len(got), len(want), got)
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %q, want %q", k, got[k], v)
		}
	}
}

func TestJavaEnv_DevProfileAndOIDCEndpoints(t *testing.T) {
	assertEnv(t, JavaEnv(sampleBacking()), map[string]string{
		"SPRING_PROFILES_ACTIVE":                      "dev",
		"SPRING_CLOUD_AWS_ENDPOINT":                   "http://fakeaws-java:4566",
		"OIDC_PROVIDERS_GOOGLE_AUTHORIZATIONENDPOINT": oidcURL("/o/oauth2/v2/auth"),
		"OIDC_PROVIDERS_GOOGLE_TOKENENDPOINT":         oidcURL("/token"),
		"OIDC_PROVIDERS_GOOGLE_USERINFOENDPOINT":      oidcURL("/v1/userinfo"),
		"OIDC_PROVIDERS_GITHUB_AUTHORIZATIONENDPOINT": oidcURL("/login/oauth/authorize"),
		"OIDC_PROVIDERS_GITHUB_TOKENENDPOINT":         oidcURL("/login/oauth/access_token"),
		"OIDC_PROVIDERS_GITHUB_USERINFOENDPOINT":      oidcURL("/user"),
	})
}

func TestGoEnv_ConnectionsAndOIDCEndpoints(t *testing.T) {
	b := sampleBacking()
	assertEnv(t, GoEnv(b), map[string]string{
		"KEIREKIPRO_ENV":                      "dev",
		"DB_HOST":                             "postgres-java",
		"DB_PORT":                             "5432",
		"DB_NAME":                             "keireki_pro",
		"DB_USERNAME":                         b.DBUser,
		"DB_PASSWORD":                         b.DBPassword,
		"REDIS_HOST":                          "redis-java",
		"REDIS_PORT":                          "6379",
		"REDIS_PASSWORD":                      b.RedisPassword,
		"JWT_SECRET":                          b.JWTSecret,
		"KEIREKIPRO_AWS_ENDPOINT":             "http://fakeaws-java:4566",
		"KEIREKIPRO_OIDC_GOOGLE_AUTH_URL":     oidcURL("/o/oauth2/v2/auth"),
		"KEIREKIPRO_OIDC_GOOGLE_TOKEN_URL":    oidcURL("/token"),
		"KEIREKIPRO_OIDC_GOOGLE_USERINFO_URL": oidcURL("/v1/userinfo"),
		"KEIREKIPRO_OIDC_GITHUB_AUTH_URL":     oidcURL("/login/oauth/authorize"),
		"KEIREKIPRO_OIDC_GITHUB_TOKEN_URL":    oidcURL("/login/oauth/access_token"),
		"KEIREKIPRO_OIDC_GITHUB_USERINFO_URL": oidcURL("/user"),
	})
}

func decodeSecret(t *testing.T, text string) map[string]string {
	t.Helper()
	var m map[string]string
	if err := json.Unmarshal([]byte(text), &m); err != nil {
		t.Fatalf("秘密の値 %q を読めません: %v", text, err)
	}
	return m
}

func TestSecrets_JavaReadsAllGoReadsOIDC(t *testing.T) {
	b := sampleBacking()
	java := JavaSecrets(b)
	wantJava := map[string]map[string]string{
		"keirekipro/rds":         {"host": "postgres-java", "port": "5432", "database": "keireki_pro", "username": b.DBUser, "password": b.DBPassword},
		"keirekipro/redis":       {"redis-host": "redis-java", "redis-port": "6379", "redis-password": b.RedisPassword},
		"keirekipro/jwt":         {"jwt-secret": b.JWTSecret},
		"keirekipro/oidc/google": {"client_id": b.Google.ID, "client_secret": b.Google.Secret},
		"keirekipro/oidc/github": {"client_id": b.GitHub.ID, "client_secret": b.GitHub.Secret},
	}
	if len(java) != len(wantJava) {
		t.Errorf("Java 版の秘密の値の名前 = %v", sortedKeys(java))
	}
	for name, want := range wantJava {
		if got := decodeSecret(t, java[name]); canonicalJSON(got) != canonicalJSON(want) {
			t.Errorf("Java 版の %s = %v, want %v", name, got, want)
		}
	}
	goSecrets := GoSecrets(b)
	if len(goSecrets) != 2 || goSecrets["keirekipro/oidc/google"] != java["keirekipro/oidc/google"] || goSecrets["keirekipro/oidc/github"] != java["keirekipro/oidc/github"] {
		t.Errorf("Go 版の秘密の値 = %v", goSecrets)
	}
}

// fakeaws に登録した秘密の値を、版の宛先のホスト名から Secrets Manager の口で読めることを確かめる。
func TestRegisterSecrets_ReadableFromVersion(t *testing.T) {
	server := httptest.NewServer(fakeaws.NewServer())
	t.Cleanup(server.Close)
	addr := server.Listener.Addr().String()
	client := &http.Client{Transport: &http.Transport{
		DialContext: func(ctx context.Context, network, _ string) (net.Conn, error) {
			var d net.Dialer
			return d.DialContext(ctx, network, addr)
		},
	}}
	ctx := t.Context()
	secrets := JavaSecrets(sampleBacking())
	if err := RegisterSecrets(ctx, client, server.URL+"/", VersionJava, secrets); err != nil {
		t.Fatalf("RegisterSecrets: %v", err)
	}

	read := func(version, name string) (string, error) {
		sm := secretsmanager.NewFromConfig(aws.Config{
			Region:       "ap-northeast-1",
			Credentials:  credentials.NewStaticCredentialsProvider("dummy", "dummy", ""),
			HTTPClient:   client,
			BaseEndpoint: aws.String("http://" + fakeaws.HostPrefix + version + ":" + fakeaws.Port),
		})
		out, err := sm.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{SecretId: aws.String(name)})
		if err != nil {
			return "", err
		}
		return aws.ToString(out.SecretString), nil
	}
	for name, want := range secrets {
		if got, err := read(VersionJava, name); err != nil || got != want {
			t.Errorf("Java 版の %s = %q, %v, want %q", name, got, err, want)
		}
	}
	if _, err := read(VersionGo, "keirekipro/rds"); err == nil {
		t.Error("Go 版に登録していない秘密の値を読めました")
	}
}

func TestRegisterSecrets_FailsOnRejection(t *testing.T) {
	var mu sync.Mutex
	var paths []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		mu.Lock()
		paths = append(paths, r.Method+" "+r.URL.EscapedPath()+" "+string(body))
		mu.Unlock()
		if strings.HasSuffix(r.URL.Path, "/b") {
			http.Error(w, "拒否", http.StatusBadRequest)
		}
	}))
	t.Cleanup(server.Close)

	err := RegisterSecrets(t.Context(), server.Client(), server.URL, "go v", map[string]string{"c": "3", "a/x": "1", "b": "2"})
	if err == nil || !strings.Contains(err.Error(), "b の登録が 400 で断られました: 拒否") {
		t.Fatalf("RegisterSecrets の誤り = %v", err)
	}
	mu.Lock()
	defer mu.Unlock()
	// 名前の順に登録し、断られたところで止める。
	want := []string{"PUT /_compat/go%20v/secrets/a/x 1", "PUT /_compat/go%20v/secrets/b 2"}
	if strings.Join(paths, "|") != strings.Join(want, "|") {
		t.Errorf("届いた要求 = %v, want %v", paths, want)
	}

	if err := RegisterSecrets(t.Context(), server.Client(), "http://127.0.0.1:1", "go", map[string]string{"a": "1"}); err == nil {
		t.Error("届かない宛先で誤りになりません")
	}
	if err := RegisterSecrets(t.Context(), server.Client(), "http://\x7f", "go", map[string]string{"a": "1"}); err == nil {
		t.Error("読めない宛先で誤りになりません")
	}
}

func TestVersionsEnv_TLS(t *testing.T) {
	b := sampleBacking()
	b.TrustStore = TrustStorePath
	b.TrustStorePassword = sample("store")
	b.CACert = CACertPath
	java := JavaEnv(b)
	want := "-Djavax.net.ssl.trustStore=" + TrustStorePath +
		" -Djavax.net.ssl.trustStorePassword=" + b.TrustStorePassword +
		" -Djavax.net.ssl.trustStoreType=PKCS12"
	if java["JAVA_TOOL_OPTIONS"] != want {
		t.Errorf("Java 版の JAVA_TOOL_OPTIONS = %q, want %q", java["JAVA_TOOL_OPTIONS"], want)
	}
	if _, ok := java["SSL_CERT_FILE"]; ok {
		t.Error("Java 版に SSL_CERT_FILE を渡しています")
	}
	goEnv := GoEnv(b)
	if goEnv["SSL_CERT_FILE"] != CACertPath {
		t.Errorf("Go 版の SSL_CERT_FILE = %q, want %q", goEnv["SSL_CERT_FILE"], CACertPath)
	}
	if _, ok := goEnv["JAVA_TOOL_OPTIONS"]; ok {
		t.Error("Go 版に JAVA_TOOL_OPTIONS を渡しています")
	}
	// 置き場が空なら、どちらの版にも渡さない(TLS の別名を使わない検査の土台のテストのため)
	plain := sampleBacking()
	if _, ok := JavaEnv(plain)["JAVA_TOOL_OPTIONS"]; ok {
		t.Error("信頼の束が無いのに、Java 版に JAVA_TOOL_OPTIONS を渡しています")
	}
	if _, ok := GoEnv(plain)["SSL_CERT_FILE"]; ok {
		t.Error("認証局の証明書が無いのに、Go 版に SSL_CERT_FILE を渡しています")
	}
}

// specFile は、spec の、コンテナの中のパス path に写すファイルを返す。無ければ nil を返す。
func specFile(spec ContainerSpec, path string) *testcontainers.ContainerFile {
	for i := range spec.Files {
		if spec.Files[i].ContainerFilePath == path {
			return &spec.Files[i]
		}
	}
	return nil
}

func TestBackendSpec_CopiesTLSFiles(t *testing.T) {
	a, err := NewTLSAlias(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	fk := &fakes{jwtSecret: sample("jwt"), tls: a}
	b := fk.backingFor(&Store{dbHost: "postgres", redisHost: "redis"}, "fakeaws")
	if b.TrustStore != TrustStorePath || b.CACert != CACertPath || b.TrustStorePassword != a.TrustStorePassword {
		t.Errorf("つなぐ先の置き場 = %q %q %q, want %q %q と信頼の束のパスワード", b.TrustStore, b.CACert, b.TrustStorePassword, TrustStorePath, CACertPath)
	}

	// Java 版は、信頼の束を作る前には起動の形を作れない
	if _, err := backendSpec(VersionJava, JavaBackend("java-image"), b); err == nil {
		t.Error("信頼の束を作る前に、Java 版の起動の形を作れました")
	}
	a.TrustStoreFile = filepath.Join(filepath.Dir(a.CACertFile), "truststore.p12")
	java, err := backendSpec(VersionJava, JavaBackend("java-image"), b)
	if err != nil {
		t.Fatal(err)
	}
	if f := specFile(java, TrustStorePath); f == nil || f.HostFilePath != a.TrustStoreFile {
		t.Errorf("Java 版に写す信頼の束 = %+v, want %s", f, a.TrustStoreFile)
	}
	if f := specFile(java, CACertPath); f == nil || f.HostFilePath != a.CACertFile {
		t.Errorf("Java 版に写す認証局の証明書 = %+v, want %s", f, a.CACertFile)
	}
	if java.Env["JAVA_TOOL_OPTIONS"] == "" || java.Name != "backend-"+VersionJava || java.Image != "java-image" {
		t.Errorf("Java 版の起動の形 = %+v", java)
	}

	goSpec, err := backendSpec(VersionGo, GoBackend("go-image"), b)
	if err != nil {
		t.Fatal(err)
	}
	if f := specFile(goSpec, CACertPath); f == nil || f.HostFilePath != a.CACertFile {
		t.Errorf("Go 版に写す認証局の証明書 = %+v, want %s", f, a.CACertFile)
	}
	if specFile(goSpec, TrustStorePath) != nil {
		t.Error("Go 版にも信頼の束を写しています")
	}
	if goSpec.Env["SSL_CERT_FILE"] != CACertPath {
		t.Errorf("Go 版の SSL_CERT_FILE = %q", goSpec.Env["SSL_CERT_FILE"])
	}
	for _, s := range []ContainerSpec{java, goSpec} {
		for _, file := range s.Files {
			if file.FileMode != 0o644 {
				t.Errorf("%s に写す %s の権限 = %o, want 0644(root でない利用者が読める)", s.Name, file.ContainerFilePath, file.FileMode)
			}
		}
	}

	// TLS の別名が無ければ、何も写さず、置き場も渡さない
	plain := (&fakes{}).backingFor(&Store{}, "fakeaws")
	if plain.TrustStore != "" || plain.CACert != "" {
		t.Errorf("TLS の別名が無いときの置き場 = %q %q, want 空", plain.TrustStore, plain.CACert)
	}
	spec, err := backendSpec(VersionJava, JavaBackend("java-image"), plain)
	if err != nil || len(spec.Files) != 0 {
		t.Errorf("TLS の別名が無いときの Java 版の起動の形 = %+v, %v, want 写すファイル無し", spec.Files, err)
	}
}

func TestFakeOIDCSpec_TLS(t *testing.T) {
	a, err := NewTLSAlias(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	spec := fakeOIDCSpec("oidc-image", a)
	if spec.Name != "fakeoidc" || spec.Image != "oidc-image" || len(spec.Aliases) != 1 || spec.Aliases[0] != GitHubAPIHost {
		t.Errorf("fakeoidc の起動の形 = %+v, want 名前 fakeoidc と別名 %s", spec, GitHubAPIHost)
	}
	if spec.Env[fakeoidc.CertFileEnv] != TLSCertPath || spec.Env[fakeoidc.KeyFileEnv] != TLSKeyPath {
		t.Errorf("fakeoidc の環境変数 = %v", spec.Env)
	}
	if f := specFile(spec, TLSCertPath); f == nil || f.HostFilePath != a.CertFile || f.FileMode != 0o644 {
		t.Errorf("fakeoidc に写す証明書 = %+v", f)
	}
	if f := specFile(spec, TLSKeyPath); f == nil || f.HostFilePath != a.KeyFile || f.FileMode != 0o644 {
		t.Errorf("fakeoidc に写す鍵 = %+v", f)
	}
	if spec.WaitingFor == nil || len(spec.ExposedPorts) != 1 || spec.ExposedPorts[0] != fakeoidc.Port+"/tcp" {
		t.Errorf("fakeoidc の外に出すポートと待ち方 = %v %v", spec.ExposedPorts, spec.WaitingFor)
	}
}
