//go:build compat

package harness

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeoidc"
)

// 比べる検査が動かす版の名前である。fakeaws は、要求の宛先のホスト名 fakeaws-<版> で版を分ける。
const (
	VersionJava = "java"
	VersionGo   = "go"
)

// 秘密の値の名前である。Java 版の application-dev.yaml と application.yaml の名前と同じにしている。
const (
	paramNameRDS    = "keirekipro/rds"
	paramNameRedis  = "keirekipro/redis"
	paramNameJWT    = "keirekipro/jwt"
	paramNameGoogle = "keirekipro/oidc/google"
	paramNameGitHub = "keirekipro/oidc/github"
)

// Backing は、1つの版がつなぐ先である。比べる検査では、Java 版と Go 版は別々のデータベースと Redis につなぎ、
// 版をまたぐ確認では同じものにつなぐ。どちらも、同じ JWT の値と、同じ fakeoidc のクライアントを使う。
type Backing struct {
	DBHost     string
	DBPort     string
	DBName     string
	DBUser     string
	DBPassword string

	RedisHost     string
	RedisPort     string
	RedisPassword string

	JWTSecret string

	// AWSEndpoint は、fakeaws の URL である。版を分けるため、ホスト名は fakeaws-java か fakeaws-go にする。
	AWSEndpoint string
	// OIDCBaseURL は、ネットワークの中から fakeoidc を呼ぶ URL(例: http://fakeoidc:8080)である。
	OIDCBaseURL string
	Google      fakeoidc.Client
	GitHub      fakeoidc.Client
}

// oidcPaths は、fakeoidc が本物と同じパスで受ける、提供元ごとの認可と token と利用者の口のパスである。
var oidcPaths = map[string][3]string{
	fakeoidc.Google: {"/o/oauth2/v2/auth", "/token", "/v1/userinfo"},
	fakeoidc.GitHub: {"/login/oauth/authorize", "/login/oauth/access_token", "/user"},
}

// JavaEnv は、Java 版のコンテナの環境変数を返す。Java 版は、dev のプロファイルで、データベースと Redis と JWT の値を
// fakeaws の秘密の値から読む。そのため、比べる検査は、Java 版を起動する前に JavaSecrets を fakeaws に登録する。
func JavaEnv(b Backing) map[string]string {
	env := map[string]string{
		"SPRING_PROFILES_ACTIVE":    "dev",
		"SPRING_CLOUD_AWS_ENDPOINT": b.AWSEndpoint,
	}
	for _, provider := range []string{fakeoidc.Google, fakeoidc.GitHub} {
		prefix := "OIDC_PROVIDERS_" + strings.ToUpper(provider) + "_"
		paths := oidcPaths[provider]
		env[prefix+"AUTHORIZATIONENDPOINT"] = b.OIDCBaseURL + paths[0]
		env[prefix+"TOKENENDPOINT"] = b.OIDCBaseURL + paths[1]
		env[prefix+"USERINFOENDPOINT"] = b.OIDCBaseURL + paths[2]
	}
	return env
}

// GoEnv は、Go 版のコンテナの環境変数を返す。Go 版は、dev ではデータベースと Redis と JWT の値を環境変数から読み、
// 外部のログインのクライアントの値だけを fakeaws の秘密の値から読む。
func GoEnv(b Backing) map[string]string {
	env := map[string]string{
		"KEIREKIPRO_ENV":          "dev",
		"DB_HOST":                 b.DBHost,
		"DB_PORT":                 b.DBPort,
		"DB_NAME":                 b.DBName,
		"DB_USERNAME":             b.DBUser,
		"DB_PASSWORD":             b.DBPassword,
		"REDIS_HOST":              b.RedisHost,
		"REDIS_PORT":              b.RedisPort,
		"REDIS_PASSWORD":          b.RedisPassword,
		"JWT_SECRET":              b.JWTSecret,
		"KEIREKIPRO_AWS_ENDPOINT": b.AWSEndpoint,
	}
	for _, provider := range []string{fakeoidc.Google, fakeoidc.GitHub} {
		prefix := "KEIREKIPRO_OIDC_" + strings.ToUpper(provider) + "_"
		paths := oidcPaths[provider]
		env[prefix+"AUTH_URL"] = b.OIDCBaseURL + paths[0]
		env[prefix+"TOKEN_URL"] = b.OIDCBaseURL + paths[1]
		env[prefix+"USERINFO_URL"] = b.OIDCBaseURL + paths[2]
	}
	return env
}

// JavaSecrets は、Java 版のために fakeaws に登録する秘密の値を、名前ごとの JSON の文字で返す。
func JavaSecrets(b Backing) map[string]string {
	secrets := oidcSecrets(b)
	secrets[paramNameRDS] = canonicalJSON(map[string]string{
		"host": b.DBHost, "port": b.DBPort, "database": b.DBName, "username": b.DBUser, "password": b.DBPassword,
	})
	secrets[paramNameRedis] = canonicalJSON(map[string]string{
		"redis-host": b.RedisHost, "redis-port": b.RedisPort, "redis-password": b.RedisPassword,
	})
	secrets[paramNameJWT] = canonicalJSON(map[string]string{"jwt-secret": b.JWTSecret})
	return secrets
}

// GoSecrets は、Go 版のために fakeaws に登録する秘密の値を、名前ごとの JSON の文字で返す。
func GoSecrets(b Backing) map[string]string {
	return oidcSecrets(b)
}

func oidcSecrets(b Backing) map[string]string {
	return map[string]string{
		paramNameGoogle: canonicalJSON(map[string]string{"client_id": b.Google.ID, "client_secret": b.Google.Secret}),
		paramNameGitHub: canonicalJSON(map[string]string{"client_id": b.GitHub.ID, "client_secret": b.GitHub.Secret}),
	}
}

// RegisterSecrets は、fakeaws の版 version に秘密の値を登録する。baseURL は、テストの処理から届く fakeaws の URL である。
func RegisterSecrets(ctx context.Context, client *http.Client, baseURL, version string, secrets map[string]string) error {
	for _, name := range sortedKeys(secrets) {
		target := strings.TrimSuffix(baseURL, "/") + "/_compat/" + url.PathEscape(version) + "/secrets/" + name
		req, err := http.NewRequestWithContext(ctx, http.MethodPut, target, strings.NewReader(secrets[name]))
		if err != nil {
			return fmt.Errorf("harness: 秘密の値 %s の登録の要求を作れません: %w", name, err)
		}
		resp, err := client.Do(req)
		if err != nil {
			return fmt.Errorf("harness: 秘密の値 %s を登録できません: %w", name, err)
		}
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		_ = resp.Body.Close()
		if resp.StatusCode/100 != 2 {
			return fmt.Errorf("harness: 秘密の値 %s の登録が %d で断られました: %s", name, resp.StatusCode, body)
		}
	}
	return nil
}
