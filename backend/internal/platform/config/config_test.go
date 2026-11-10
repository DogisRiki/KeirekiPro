package config

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// テストで環境変数に渡す値である。
// gosec は、PASSWORD や TOKEN を名前に含むキーに文字列をじかに書くと秘密の値の書き込みとみなすので、名前付きの定数にする。
const (
	valueDevDB      = "dev-password"
	valueDevRedis   = "dev-redis-password"
	valueDevJWT     = "dev-jwt-secret"
	urlGoogleAuth   = "http://fakeoidc/google/auth"
	urlGitHubAccess = "http://fakeoidc/github/token"
	urlGitHubUser   = "http://fakeoidc/github/user"
	urlGoogleAccess = "https://oauth2.googleapis.com/token"
	valueGoogle     = "google-secret-value"
	valueGitHub     = "github-secret-value"
)

// fakeSecretsManager は、Secrets Manager の GetSecretValue だけに答えるサーバである。
// secrets に無い名前には、AWS と同じ ResourceNotFoundException を返す。
func fakeSecretsManager(t *testing.T, secrets map[string]string) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if target := r.Header.Get("X-Amz-Target"); target != "secretsmanager.GetSecretValue" {
			t.Errorf("想定しない要求 %q", target)
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		var input struct{ SecretId string }
		if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
			t.Errorf("要求の本文を読めません: %v", err)
		}
		w.Header().Set("Content-Type", "application/x-amz-json-1.1")
		value, ok := secrets[input.SecretId]
		if !ok {
			w.Header().Set("X-Amzn-ErrorType", "ResourceNotFoundException")
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"__type":"ResourceNotFoundException","message":"Secrets Manager can't find the specified secret."}`))
			return
		}
		body, err := json.Marshal(map[string]string{"Name": input.SecretId, "SecretString": value})
		if err != nil {
			t.Errorf("応答を作れません: %v", err)
		}
		_, _ = w.Write(body)
	}))
	t.Cleanup(server.Close)
	return server
}

// oidcSecrets は、dev と test でも Secrets Manager から読む、外部のログインの2つの秘密の値である。
func oidcSecrets() map[string]string {
	return map[string]string{
		"keirekipro/oidc/google": `{"client_id":"google-id","client_secret":"` + valueGoogle + `"}`,
		"keirekipro/oidc/github": `{"client_id":"github-id","client_secret":"` + valueGitHub + `"}`,
	}
}

// prodSecrets は、本番の5つの秘密の値である。キーの名前は terraform/main.tf と同じである。
func prodSecrets() map[string]string {
	secrets := oidcSecrets()
	secrets["keirekipro/rds"] = `{"host":"rds.example","port":"5433","database":"keireki","username":"app","password":"rds-password-value"}`
	secrets["keirekipro/redis"] = `{"redis-host":"redis.example","redis-port":"6380","redis-password":"redis-password-value","redis-username":"app-user",` +
		`"spring.data.redis.cluster.nodes":"redis.example:6380","spring.data.redis.username":"app-user"}`
	secrets["keirekipro/jwt"] = `{"jwt-secret":"jwt-secret-value"}`
	return secrets
}

// envOf は、渡した組だけを持つ環境変数の読み手を作る。
func envOf(values map[string]string) Lookup {
	return func(key string) (string, bool) {
		value, ok := values[key]
		return value, ok
	}
}

// 本番では、5つの秘密の値の決まったキーを読み、Java 版の application-prod.yaml と同じ既定の値を持つことを確かめる。
func TestLoad_ProdReadsSecretKeys(t *testing.T) {
	server := fakeSecretsManager(t, prodSecrets())
	cfg, err := Load(t.Context(), envOf(map[string]string{
		"KEIREKIPRO_ENV":          "prod",
		"KEIREKIPRO_AWS_ENDPOINT": server.URL,
		// 本番では、dev と test の環境変数を読まない
		"DB_HOST":    "ignored",
		"JWT_SECRET": "ignored",
	}))
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	if cfg.Env != EnvProd {
		t.Errorf("Env = %q, want prod", cfg.Env)
	}
	wantDB := database.Options{Host: "rds.example", Port: 5433, Database: "keireki", User: "app", Password: "rds-password-value"}
	if cfg.Database != wantDB {
		t.Errorf("Database = %+v, want %+v", cfg.Database, wantDB)
	}
	wantRedis := redisstore.Options{Addr: "redis.example:6380", Username: "app-user", Password: "redis-password-value", Cluster: true, TLS: true}
	if cfg.Redis != wantRedis {
		t.Errorf("Redis = %+v, want %+v", cfg.Redis, wantRedis)
	}
	if cfg.JWT.Secret != "jwt-secret-value" {
		t.Errorf("JWT.Secret = %q, want jwt-secret-value", cfg.JWT.Secret)
	}
	if cfg.OIDC.Google.ClientID != "google-id" || cfg.OIDC.Google.ClientSecret != "google-secret-value" {
		t.Errorf("OIDC.Google = %+v", cfg.OIDC.Google)
	}
	if cfg.OIDC.GitHub.ClientID != "github-id" || cfg.OIDC.GitHub.ClientSecret != "github-secret-value" {
		t.Errorf("OIDC.GitHub = %+v", cfg.OIDC.GitHub)
	}
	if cfg.AWS.Region != "ap-northeast-1" || cfg.AWS.Endpoint != server.URL {
		t.Errorf("AWS = %+v", cfg.AWS)
	}

	wantApp := App{
		SiteName:           "KeirekiPro",
		SiteURL:            "https://app.keirekipro.click",
		APIBaseURL:         "https://app.keirekipro.click",
		FrontendBaseURL:    "https://app.keirekipro.click",
		CORSAllowedOrigins: []string{"https://app.keirekipro.click"},
		CookieSecure:       true,
		SESFromAddress:     "info@keirekipro.click",
		S3Bucket:           "keirekipro-storage",
	}
	assertApp(t, cfg.App, wantApp)
	assertTokenValidity(t, cfg.JWT)
}

// 足りないキーと読めない秘密の値を、値を書かずに、秘密の値の名前とキーの名前でエラーにすることを確かめる。
func TestLoad_MissingKeyErrorHasNoValue(t *testing.T) {
	values := []string{"rds-password-value", "redis-password-value", "jwt-secret-value", "google-secret-value", "github-secret-value", "rds.example", "not-a-port"}
	cases := []struct {
		name   string
		change func(secrets map[string]string)
		want   []string
	}{
		{
			name: "キーが無い",
			change: func(s map[string]string) {
				s["keirekipro/rds"] = `{"host":"rds.example","port":"5433","database":"keireki","username":"app"}`
			},
			want: []string{"keirekipro/rds", "password"},
		},
		{
			name: "キーの値が空",
			change: func(s map[string]string) {
				s["keirekipro/jwt"] = `{"jwt-secret":""}`
			},
			want: []string{"keirekipro/jwt", "jwt-secret"},
		},
		{
			name: "利用者の名前が無い Redis の秘密の値",
			change: func(s map[string]string) {
				s["keirekipro/redis"] = `{"redis-host":"redis.example","redis-port":"6380","redis-password":"redis-password-value"}`
			},
			want: []string{"keirekipro/redis", "redis-username"},
		},
		{
			name: "ポートが数でない",
			change: func(s map[string]string) {
				s["keirekipro/rds"] = `{"host":"rds.example","port":"not-a-port","database":"keireki","username":"app","password":"rds-password-value"}`
			},
			want: []string{"keirekipro/rds", "port"},
		},
		{
			name: "中身が JSON でない",
			change: func(s map[string]string) {
				s["keirekipro/oidc/github"] = `client_secret=github-secret-value`
			},
			want: []string{"keirekipro/oidc/github"},
		},
		{
			name: "秘密の値が無い",
			change: func(s map[string]string) {
				delete(s, "keirekipro/oidc/google")
			},
			want: []string{"keirekipro/oidc/google"},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			secrets := prodSecrets()
			tc.change(secrets)
			server := fakeSecretsManager(t, secrets)
			_, err := Load(t.Context(), envOf(map[string]string{"KEIREKIPRO_ENV": "prod", "KEIREKIPRO_AWS_ENDPOINT": server.URL}))
			if err == nil {
				t.Fatal("Load の誤り = nil, want 誤り")
			}
			for _, want := range tc.want {
				if !strings.Contains(err.Error(), want) {
					t.Errorf("誤り %q に %q がありません", err, want)
				}
			}
			for _, value := range values {
				if strings.Contains(err.Error(), value) {
					t.Errorf("誤り %q に値 %q が書かれています", err, value)
				}
			}
		})
	}
}

// dev では、Java 版の application.yaml と同じ名前の環境変数を読み、外部のログインの秘密の値を Secrets Manager から読むことを確かめる。
func TestLoad_DevReadsJavaEnvNames(t *testing.T) {
	server := fakeSecretsManager(t, oidcSecrets())
	cfg, err := Load(t.Context(), envOf(map[string]string{
		"KEIREKIPRO_ENV":          "dev",
		"KEIREKIPRO_AWS_ENDPOINT": server.URL,
		"DB_HOST":                 "db",
		"DB_PORT":                 "15432",
		"DB_NAME":                 "keireki_dev",
		"DB_USERNAME":             "dev-user",
		"DB_PASSWORD":             valueDevDB,
		"REDIS_HOST":              "redis",
		"REDIS_PORT":              "16379",
		"REDIS_PASSWORD":          valueDevRedis,
		"JWT_SECRET":              valueDevJWT,
	}))
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	wantDB := database.Options{Host: "db", Port: 15432, Database: "keireki_dev", User: "dev-user", Password: valueDevDB}
	if cfg.Database != wantDB {
		t.Errorf("Database = %+v, want %+v", cfg.Database, wantDB)
	}
	wantRedis := redisstore.Options{Addr: "redis:16379", Password: valueDevRedis}
	if cfg.Redis != wantRedis {
		t.Errorf("Redis = %+v, want %+v", cfg.Redis, wantRedis)
	}
	if cfg.JWT.Secret != valueDevJWT {
		t.Errorf("JWT.Secret = %q, want %q", cfg.JWT.Secret, valueDevJWT)
	}
	if cfg.OIDC.Google.ClientID != "google-id" || cfg.OIDC.GitHub.ClientSecret != "github-secret-value" {
		t.Errorf("OIDC = %+v", cfg.OIDC)
	}
	if cfg.AWS.Endpoint != server.URL {
		t.Errorf("AWS.Endpoint = %q, want %q", cfg.AWS.Endpoint, server.URL)
	}

	t.Run("ポートが数でない", func(t *testing.T) {
		_, err := Load(t.Context(), envOf(map[string]string{"KEIREKIPRO_AWS_ENDPOINT": server.URL, "REDIS_PORT": "not-a-port"}))
		if err == nil || !strings.Contains(err.Error(), "REDIS_PORT") || strings.Contains(err.Error(), "not-a-port") {
			t.Errorf("Load の誤り = %v, want REDIS_PORT の名前だけを書いた誤り", err)
		}
	})
}

// KEIREKIPRO_ENV が無ければ dev になり、Java 版の application.yaml と application-dev.yaml と同じ既定の値を持つことを確かめる。
// test の既定の値は dev と同じである。
func TestLoad_DefaultEnvIsDev(t *testing.T) {
	server := fakeSecretsManager(t, oidcSecrets())
	for _, tc := range []struct {
		name    string
		env     map[string]string
		wantEnv Env
	}{
		{name: "KEIREKIPRO_ENV が無い", env: map[string]string{}, wantEnv: EnvDev},
		{name: "KEIREKIPRO_ENV が test", env: map[string]string{"KEIREKIPRO_ENV": "test"}, wantEnv: EnvTest},
	} {
		t.Run(tc.name, func(t *testing.T) {
			tc.env["KEIREKIPRO_AWS_ENDPOINT"] = server.URL
			cfg, err := Load(t.Context(), envOf(tc.env))
			if err != nil {
				t.Fatalf("Load: %v", err)
			}
			if cfg.Env != tc.wantEnv {
				t.Errorf("Env = %q, want %q", cfg.Env, tc.wantEnv)
			}
			wantDB := database.Options{Host: "localhost", Port: 5432, Database: "keireki_pro", User: "postgres", Password: "postgres"}
			if cfg.Database != wantDB {
				t.Errorf("Database = %+v, want %+v", cfg.Database, wantDB)
			}
			wantRedis := redisstore.Options{Addr: "localhost:6379"}
			if cfg.Redis != wantRedis {
				t.Errorf("Redis = %+v, want %+v", cfg.Redis, wantRedis)
			}
			if cfg.JWT.Secret != "default-jwt-secret-for-development" {
				t.Errorf("JWT.Secret = %q", cfg.JWT.Secret)
			}
			wantApp := App{
				SiteName:           "KeirekiPro",
				SiteURL:            "https://app.keirekipro.click",
				FrontendBaseURL:    "http://localhost:5173",
				CORSAllowedOrigins: []string{"http://localhost:5173", "http://localhost:8082"},
				SESFromAddress:     "no-reply@keirekipro.click",
				S3Bucket:           "keirekipro-storage",
			}
			assertApp(t, cfg.App, wantApp)
			assertTokenValidity(t, cfg.JWT)
		})
	}

	t.Run("dev の AWS の接続先の既定は Java 版と同じ localstack", func(t *testing.T) {
		if got := defaultAWSEndpoint(EnvDev); got != "http://localstack:4566" {
			t.Errorf("dev の接続先 = %q, want http://localstack:4566", got)
		}
		if got := defaultAWSEndpoint(EnvTest); got != "http://localstack:4566" {
			t.Errorf("test の接続先 = %q, want http://localstack:4566", got)
		}
		if got := defaultAWSEndpoint(EnvProd); got != "" {
			t.Errorf("prod の接続先 = %q, want 空", got)
		}
	})

	t.Run("KEIREKIPRO_ENV が決まった値でない", func(t *testing.T) {
		_, err := Load(t.Context(), envOf(map[string]string{"KEIREKIPRO_ENV": "staging"}))
		if err == nil || !strings.Contains(err.Error(), "KEIREKIPRO_ENV") {
			t.Errorf("Load の誤り = %v, want KEIREKIPRO_ENV の誤り", err)
		}
	})
}

// CORS の許す送り元が、prod では画面の送り元の1つだけで、dev と test では画面と API の説明画面の2つであることを確かめる。
// dev と test で API の説明画面の送り元を許すのは、開発者が説明画面の「Try it out」で Go 版を呼べるようにするためである(CB-010)。
func TestLoad_CORSAllowedOriginsByEnv(t *testing.T) {
	devOrigins := []string{"http://localhost:5173", "http://localhost:8082"}
	for _, tc := range []struct {
		env     string
		secrets map[string]string
		want    []string
	}{
		{env: "prod", secrets: prodSecrets(), want: []string{"https://app.keirekipro.click"}},
		{env: "dev", secrets: oidcSecrets(), want: devOrigins},
		{env: "test", secrets: oidcSecrets(), want: devOrigins},
	} {
		t.Run(tc.env, func(t *testing.T) {
			server := fakeSecretsManager(t, tc.secrets)
			cfg, err := Load(t.Context(), envOf(map[string]string{"KEIREKIPRO_ENV": tc.env, "KEIREKIPRO_AWS_ENDPOINT": server.URL}))
			if err != nil {
				t.Fatalf("Load: %v", err)
			}
			if !reflect.DeepEqual(cfg.App.CORSAllowedOrigins, tc.want) {
				t.Errorf("CORSAllowedOrigins = %v, want %v", cfg.App.CORSAllowedOrigins, tc.want)
			}
		})
	}
}

// 外部のログインの接続先の URL を KEIREKIPRO_OIDC_* で替えられ、替えない URL は Java 版と同じ既定のままであることを確かめる。
func TestLoad_OIDCEndpointOverride(t *testing.T) {
	server := fakeSecretsManager(t, oidcSecrets())
	cfg, err := Load(t.Context(), envOf(map[string]string{
		"KEIREKIPRO_AWS_ENDPOINT":             server.URL,
		"KEIREKIPRO_OIDC_GOOGLE_AUTH_URL":     urlGoogleAuth,
		"KEIREKIPRO_OIDC_GITHUB_TOKEN_URL":    urlGitHubAccess,
		"KEIREKIPRO_OIDC_GITHUB_USERINFO_URL": urlGitHubUser,
	}))
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	wantGoogle := Provider{
		AuthURL:      urlGoogleAuth,
		TokenURL:     urlGoogleAccess,
		UserInfoURL:  "https://openidconnect.googleapis.com/v1/userinfo",
		Scopes:       "openid email profile",
		ClientID:     "google-id",
		ClientSecret: valueGoogle,
	}
	if cfg.OIDC.Google != wantGoogle {
		t.Errorf("OIDC.Google = %+v, want %+v", cfg.OIDC.Google, wantGoogle)
	}
	wantGitHub := Provider{
		AuthURL:      "https://github.com/login/oauth/authorize",
		TokenURL:     urlGitHubAccess,
		UserInfoURL:  urlGitHubUser,
		Scopes:       "read:user user:email",
		ClientID:     "github-id",
		ClientSecret: valueGitHub,
	}
	if cfg.OIDC.GitHub != wantGitHub {
		t.Errorf("OIDC.GitHub = %+v, want %+v", cfg.OIDC.GitHub, wantGitHub)
	}
}

func assertApp(t *testing.T, got, want App) {
	t.Helper()
	if !reflect.DeepEqual(got, want) {
		t.Errorf("App = %+v, want %+v", got, want)
	}
}

func assertTokenValidity(t *testing.T, jwt JWT) {
	t.Helper()
	if jwt.AccessTokenValidity != 10*time.Minute || jwt.RefreshTokenValidity != 7*24*time.Hour {
		t.Errorf("トークンの有効な時間 = (%v, %v), want (10m, 168h)", jwt.AccessTokenValidity, jwt.RefreshTokenValidity)
	}
}
