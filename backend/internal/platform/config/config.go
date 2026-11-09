// Package config は、起動時に1回だけ、環境変数と Secrets Manager から設定を読む。
// 既定の値は、Java 版の application.yaml と application-prod.yaml と application-dev.yaml と同じにする。
package config

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/awsclient"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// Env は、動かす環境の名前である。
type Env string

// 環境の名前の3つの値である。
const (
	EnvProd Env = "prod"
	EnvDev  Env = "dev"
	EnvTest Env = "test"
)

// Lookup は、環境変数を1つ読む関数である。起動の入口は os.LookupEnv を渡す。
type Lookup func(key string) (string, bool)

// App は、サイトと画面と Cookie と送り先の設定である。
type App struct {
	SiteName string
	SiteURL  string
	// APIBaseURL は、本番で API の URL を組み立てる元である。dev と test では空にし、要求から組み立てる。
	APIBaseURL         string
	FrontendBaseURL    string
	CORSAllowedOrigins []string
	CookieSecure       bool
	SESFromAddress     string
	S3Bucket           string
}

// JWT は、ログインの状態を表すトークンの設定である。
type JWT struct {
	Secret               string
	AccessTokenValidity  time.Duration
	RefreshTokenValidity time.Duration
}

// Provider は、外部のログインの1つの提供元の設定である。
type Provider struct {
	AuthURL      string
	TokenURL     string
	UserInfoURL  string
	Scopes       string
	ClientID     string
	ClientSecret string
}

// OIDC は、外部のログインの2つの提供元の設定である。
type OIDC struct {
	Google Provider
	GitHub Provider
}

// Config は、Go 版の設定のすべてである。
type Config struct {
	Env      Env
	App      App
	JWT      JWT
	OIDC     OIDC
	Database database.Options
	Redis    redisstore.Options
	AWS      awsclient.Options
}

// region は、Java 版の spring.cloud.aws.region.static と同じリージョンである。
const region = "ap-northeast-1"

// localstackEndpoint は、Java 版の application-dev.yaml の spring.cloud.aws.endpoint と同じ値である。
const localstackEndpoint = "http://localstack:4566"

// 秘密の値の名前である。terraform の Secrets Manager の秘密の値と同じ名前にする。
const (
	nameRDS    = "keirekipro/rds"
	nameRedis  = "keirekipro/redis"
	nameJWT    = "keirekipro/jwt"
	nameGoogle = "keirekipro/oidc/google"
	nameGitHub = "keirekipro/oidc/github"
)

// defaultAWSEndpoint は、KEIREKIPRO_AWS_ENDPOINT が無いときの AWS の接続先である。本番は空にし、本当の AWS につなぐ。
func defaultAWSEndpoint(env Env) string {
	if env == EnvProd {
		return ""
	}
	return localstackEndpoint
}

// Load は、環境変数と Secrets Manager から設定を読む。
// 足りない値と読めない秘密の値は、値を書かずに、名前だけでエラーにする。
func Load(ctx context.Context, lookup Lookup) (Config, error) {
	env, err := loadEnv(lookup)
	if err != nil {
		return Config{}, err
	}
	cfg := Config{
		Env:  env,
		App:  defaultApp(env),
		JWT:  JWT{AccessTokenValidity: 10 * time.Minute, RefreshTokenValidity: 7 * 24 * time.Hour},
		OIDC: defaultOIDC(lookup),
		AWS:  awsclient.Options{Region: region, Endpoint: getenv(lookup, "KEIREKIPRO_AWS_ENDPOINT", defaultAWSEndpoint(env))},
	}

	clients, err := awsclient.New(ctx, cfg.AWS)
	if err != nil {
		return Config{}, fmt.Errorf("config: %w", err)
	}
	secrets := secretReader{client: clients.SecretsManager}

	if env == EnvProd {
		err = loadProdConnections(ctx, secrets, &cfg)
	} else {
		err = loadDevConnections(lookup, &cfg)
	}
	if err != nil {
		return Config{}, err
	}

	// 外部のログインの秘密の値は、Java 版と同じく、どの環境でも Secrets Manager から読む
	if err := loadOIDCClient(ctx, secrets, nameGoogle, &cfg.OIDC.Google); err != nil {
		return Config{}, err
	}
	if err := loadOIDCClient(ctx, secrets, nameGitHub, &cfg.OIDC.GitHub); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func loadEnv(lookup Lookup) (Env, error) {
	value, ok := lookup("KEIREKIPRO_ENV")
	if !ok || value == "" {
		return EnvDev, nil
	}
	switch env := Env(value); env {
	case EnvProd, EnvDev, EnvTest:
		return env, nil
	default:
		return "", fmt.Errorf("config: KEIREKIPRO_ENV は %s %s %s のどれかにしてください", EnvProd, EnvDev, EnvTest)
	}
}

// defaultApp は、環境ごとの既定の値を返す。test は dev と同じにする。
func defaultApp(env Env) App {
	app := App{
		SiteName:           "KeirekiPro",
		SiteURL:            "https://app.keirekipro.click",
		FrontendBaseURL:    "http://localhost:5173",
		CORSAllowedOrigins: []string{"http://localhost:5173"},
		SESFromAddress:     "no-reply@keirekipro.click",
		S3Bucket:           "keirekipro-storage",
	}
	if env == EnvProd {
		app.APIBaseURL = "https://app.keirekipro.click"
		app.FrontendBaseURL = "https://app.keirekipro.click"
		app.CORSAllowedOrigins = []string{"https://app.keirekipro.click"}
		app.CookieSecure = true
		app.SESFromAddress = "info@keirekipro.click"
	}
	return app
}

// defaultOIDC は、Java 版の application.yaml の oidc.providers の値を返す。接続先の URL は KEIREKIPRO_OIDC_* で替えられる。
func defaultOIDC(lookup Lookup) OIDC {
	return OIDC{
		Google: Provider{
			AuthURL:     getenv(lookup, "KEIREKIPRO_OIDC_GOOGLE_AUTH_URL", "https://accounts.google.com/o/oauth2/v2/auth"),
			TokenURL:    getenv(lookup, "KEIREKIPRO_OIDC_GOOGLE_TOKEN_URL", "https://oauth2.googleapis.com/token"),
			UserInfoURL: getenv(lookup, "KEIREKIPRO_OIDC_GOOGLE_USERINFO_URL", "https://openidconnect.googleapis.com/v1/userinfo"),
			Scopes:      "openid email profile",
		},
		GitHub: Provider{
			AuthURL:     getenv(lookup, "KEIREKIPRO_OIDC_GITHUB_AUTH_URL", "https://github.com/login/oauth/authorize"),
			TokenURL:    getenv(lookup, "KEIREKIPRO_OIDC_GITHUB_TOKEN_URL", "https://github.com/login/oauth/access_token"),
			UserInfoURL: getenv(lookup, "KEIREKIPRO_OIDC_GITHUB_USERINFO_URL", "https://api.github.com/user"),
			Scopes:      "read:user user:email",
		},
	}
}

// loadProdConnections は、本番のデータベースと Redis と JWT の値を秘密の値から読む。
func loadProdConnections(ctx context.Context, secrets secretReader, cfg *Config) error {
	rds, err := secrets.read(ctx, nameRDS, "host", "port", "database", "username", "password")
	if err != nil {
		return err
	}
	rdsPort, err := parsePort(rds["port"], nameRDS+" の port")
	if err != nil {
		return err
	}
	cfg.Database = database.Options{Host: rds["host"], Port: rdsPort, Database: rds["database"], User: rds["username"], Password: rds["password"]}

	redis, err := secrets.read(ctx, nameRedis, "redis-host", "redis-port", "redis-password", "redis-username")
	if err != nil {
		return err
	}
	if _, err := parsePort(redis["redis-port"], nameRedis+" の redis-port"); err != nil {
		return err
	}
	cfg.Redis = redisstore.Options{
		Addr:     net.JoinHostPort(redis["redis-host"], redis["redis-port"]),
		Username: redis["redis-username"],
		Password: redis["redis-password"],
		Cluster:  true,
		TLS:      true,
	}

	jwt, err := secrets.read(ctx, nameJWT, "jwt-secret")
	if err != nil {
		return err
	}
	cfg.JWT.Secret = jwt["jwt-secret"]
	return nil
}

// loadDevConnections は、dev と test のデータベースと Redis と JWT の値を、Java 版の application.yaml と同じ名前の環境変数から読む。
func loadDevConnections(lookup Lookup, cfg *Config) error {
	dbPort, err := parsePort(getenv(lookup, "DB_PORT", "5432"), "DB_PORT")
	if err != nil {
		return err
	}
	redisPort := getenv(lookup, "REDIS_PORT", "6379")
	if _, err := parsePort(redisPort, "REDIS_PORT"); err != nil {
		return err
	}
	cfg.Database = database.Options{
		Host:     getenv(lookup, "DB_HOST", "localhost"),
		Port:     dbPort,
		Database: getenv(lookup, "DB_NAME", "keireki_pro"),
		User:     getenv(lookup, "DB_USERNAME", "postgres"),
		Password: getenv(lookup, "DB_PASSWORD", "postgres"),
	}
	cfg.Redis = redisstore.Options{
		Addr:     net.JoinHostPort(getenv(lookup, "REDIS_HOST", "localhost"), redisPort),
		Password: getenv(lookup, "REDIS_PASSWORD", ""),
	}
	cfg.JWT.Secret = getenv(lookup, "JWT_SECRET", "default-jwt-secret-for-development")
	return nil
}

func loadOIDCClient(ctx context.Context, secrets secretReader, name string, provider *Provider) error {
	values, err := secrets.read(ctx, name, "client_id", "client_secret")
	if err != nil {
		return err
	}
	provider.ClientID = values["client_id"]
	provider.ClientSecret = values["client_secret"]
	return nil
}

// getenv は、環境変数を読み、無いか空なら既定の値を返す。
// Java 版の ${名前:既定} は、空の値をそのまま使う。Go 版は、空の値を渡す使い方が無いので、空を無いと同じに扱う。
func getenv(lookup Lookup, key, fallback string) string {
	if value, ok := lookup(key); ok && value != "" {
		return value
	}
	return fallback
}

// parsePort は、ポートの番号を読む。誤りには、値を書かずに name だけを書く。
func parsePort(value, name string) (int, error) {
	port, err := strconv.Atoi(value)
	if err != nil || port < 1 || port > 65535 {
		return 0, fmt.Errorf("config: %s をポートの番号として読めません", name)
	}
	return port, nil
}

// secretReader は、Secrets Manager の秘密の値を JSON として読む。
type secretReader struct {
	client *secretsmanager.Client
}

// read は、秘密の値 name を読み、keys のすべてが空でない値を持つことを確かめる。
// 誤りには、秘密の値の中身を書かない。
func (r secretReader) read(ctx context.Context, name string, keys ...string) (map[string]string, error) {
	out, err := r.client.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{SecretId: aws.String(name)})
	if err != nil {
		// Secrets Manager の誤りは、要求と応答の識別子と誤りの種類だけを持ち、秘密の値の中身を持たない
		return nil, fmt.Errorf("config: 秘密の値 %s を読めません: %w", name, err)
	}
	var values map[string]string
	if err := json.Unmarshal([]byte(aws.ToString(out.SecretString)), &values); err != nil {
		// JSON の誤りは中身の一部を含むので、誤りの中身を返さない
		return nil, fmt.Errorf("config: 秘密の値 %s の中身を、文字列の値の JSON として読めません", name)
	}
	for _, key := range keys {
		if values[key] == "" {
			return nil, fmt.Errorf("config: 秘密の値 %s にキー %s の値がありません", name, key)
		}
	}
	return values, nil
}
