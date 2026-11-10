//go:build compat

package harness

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"

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
