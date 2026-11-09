//go:build compat

package harness

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/redis/go-redis/v9"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeoidc"
)

// 版をまたぐ確認で、2つの版がつなぐ Postgres と Redis の値である。どちらの版も、ネットワークの中の名前でつなぐ。
const (
	crossDBName     = "keireki_pro"
	crossDBUser     = "postgres"
	crossDBPassword = "postgres"
	backendPort     = "8080/tcp"
	// oidcCallbackPath は、外部のログインの提供元が利用者を戻す、backend の口のパスである。
	oidcCallbackPath = "/api/auth/oidc/callback"
)

// Backend は、版をまたぐ確認で、1つの版の位置に置く backend のイメージと、その起動の仕方である。
type Backend struct {
	Image string
	// Env は、つなぐ先から、コンテナの環境変数を作る。
	Env func(Backing) map[string]string
	// HealthPath は、起動を待つときに 200 を待つパスである。
	HealthPath string
}

// JavaBackend は、Java 版のイメージを、Java 版の起動の仕方で置く。
func JavaBackend(image string) Backend {
	return Backend{Image: image, Env: JavaEnv, HealthPath: "/actuator/health"}
}

// GoBackend は、Go 版のイメージを、Go 版の起動の仕方で置く。
// 版をまたぐ確認の土台を確かめるときは、Java 版の位置にも Go 版のイメージを置く。
func GoBackend(image string) Backend {
	return Backend{Image: image, Env: GoEnv, HealthPath: "/healthz"}
}

// CrossEnv は、Java 版と Go 版を、1つの Postgres と1つの Redis と1つの fakeaws と1つの fakeoidc につないだ環境である。
// どちらの版も、同じ JWT の値と同じ外部のログインのクライアントを使うので、一方の版が出したトークンをもう一方の版が受け付ける。
type CrossEnv struct {
	// URLs は、版の名前ごとの、テストの処理から届く backend の URL である。
	URLs map[string]string
	// DBConn は、テストの処理から Postgres につなぐ接続の文字である。
	DBConn string
	// Redis は、テストの処理から Redis につなぐクライアントである。
	Redis *redis.Client
	// AWSURL は、テストの処理から届く fakeaws の URL である。
	AWSURL string

	client *http.Client
	// seeded は、表の形の履歴を適用した直後に行のあった表である。Reset は、この表の行を残す。
	seeded map[string]bool
}

// StartCrossEnv は、env のネットワークに、Postgres と Redis と fakeaws と fakeoidc と、backends の2つの版を起動する。
// images は BuildImages の結果で、Postgres と Redis と fakeaws と fakeoidc のイメージを含む。
// backends は、版の名前(VersionJava と VersionGo)ごとの、その位置に置く backend である。
// 表の形の履歴は、backend を起動する前に適用する。Go 版は起動のときに履歴を確かめるだけで、表を作らないためである。
func StartCrossEnv(ctx context.Context, env *Env, images Images, backends map[string]Backend) (*CrossEnv, error) {
	for _, version := range []string{VersionJava, VersionGo} {
		if _, ok := backends[version]; !ok {
			return nil, fmt.Errorf("harness: 版 %s の位置に置く backend がありません", version)
		}
	}
	c := &CrossEnv{URLs: map[string]string{}, client: NewHTTPClient()}

	pg, err := env.Start(ctx, ContainerSpec{
		Name:  "postgres",
		Image: images[ImagePostgres],
		Env: map[string]string{
			"POSTGRES_DB": crossDBName, "POSTGRES_USER": crossDBUser, "POSTGRES_PASSWORD": crossDBPassword,
		},
		ExposedPorts: []string{"5432/tcp"},
		// 公式のイメージは、初めの設定のために一度起動してから止め、もう一度起動する。2回目の起動の行を待つ。
		WaitingFor: wait.ForAll(
			wait.ForLog("database system is ready to accept connections").WithOccurrence(2),
			wait.ForListeningPort("5432/tcp"),
		),
	})
	if err != nil {
		return nil, err
	}
	rd, err := env.Start(ctx, ContainerSpec{
		Name:         "redis",
		Image:        images[ImageRedis],
		ExposedPorts: []string{"6379/tcp"},
		WaitingFor:   wait.ForLog("Ready to accept connections"),
	})
	if err != nil {
		return nil, err
	}
	aws, err := env.Start(ctx, ContainerSpec{
		Name:         "fakeaws",
		Image:        images[ImageFakeAWS],
		ExposedPorts: []string{fakeaws.Port + "/tcp"},
		WaitingFor:   wait.ForHTTP("/_compat/healthz").WithPort(fakeaws.Port + "/tcp"),
	})
	if err != nil {
		return nil, err
	}
	oidc, err := env.Start(ctx, ContainerSpec{
		Name:         "fakeoidc",
		Image:        images[ImageFakeOIDC],
		ExposedPorts: []string{fakeoidc.Port + "/tcp"},
		WaitingFor:   wait.ForHTTP("/_compat/healthz").WithPort(fakeoidc.Port + "/tcp"),
	})
	if err != nil {
		return nil, err
	}

	dbEndpoint, err := pg.PortEndpoint(ctx, "5432/tcp", "")
	if err != nil {
		return nil, fmt.Errorf("harness: Postgres の宛先を読めません: %w", err)
	}
	c.DBConn = "postgres://" + crossDBUser + ":" + crossDBPassword + "@" + dbEndpoint + "/" + crossDBName + "?sslmode=disable"
	if _, err := ApplyMigrations(ctx, c.DBConn); err != nil {
		return nil, err
	}
	if c.seeded, err = seededTables(ctx, c.DBConn); err != nil {
		return nil, err
	}
	redisEndpoint, err := rd.PortEndpoint(ctx, "6379/tcp", "")
	if err != nil {
		return nil, fmt.Errorf("harness: Redis の宛先を読めません: %w", err)
	}
	c.Redis = redis.NewClient(&redis.Options{Addr: redisEndpoint})
	if c.AWSURL, err = aws.BaseURL(ctx, fakeaws.Port+"/tcp"); err != nil {
		return nil, err
	}
	oidcURL, err := oidc.BaseURL(ctx, fakeoidc.Port+"/tcp")
	if err != nil {
		return nil, err
	}

	b := Backing{
		DBHost: "postgres", DBPort: "5432", DBName: crossDBName, DBUser: crossDBUser, DBPassword: crossDBPassword,
		RedisHost: "redis", RedisPort: "6379",
		JWTSecret:   rand.Text() + rand.Text(),
		AWSEndpoint: "http://fakeaws:" + fakeaws.Port,
		OIDCBaseURL: "http://fakeoidc:" + fakeoidc.Port,
		Google:      fakeoidc.Client{ID: "google-" + rand.Text(), Secret: rand.Text()},
		GitHub:      fakeoidc.Client{ID: "github-" + rand.Text(), Secret: rand.Text()},
	}
	// JavaSecrets は GoSecrets を含むので、両方の版が読む秘密の値を、共有の版に1度に登録する。
	if err := RegisterSecrets(ctx, c.client, c.AWSURL, fakeaws.SharedVersion, JavaSecrets(b)); err != nil {
		return nil, err
	}

	for _, version := range []string{VersionJava, VersionGo} {
		be := backends[version]
		ctr, err := env.Start(ctx, ContainerSpec{
			Name:         "backend-" + version,
			Image:        be.Image,
			Env:          be.Env(b),
			ExposedPorts: []string{backendPort},
			WaitingFor:   wait.ForHTTP(be.HealthPath).WithPort(backendPort),
		})
		if err != nil {
			return nil, err
		}
		if c.URLs[version], err = ctr.BaseURL(ctx, backendPort); err != nil {
			return nil, err
		}
	}

	// 外部のログインの提供元は、利用者を、要求を受けた backend の URL の口に戻す。テストの処理は外に出したポートで
	// backend を呼ぶので、2つの版のその URL を、転送してよい先に登録する。
	var redirects []string
	for _, version := range []string{VersionJava, VersionGo} {
		redirects = append(redirects, c.URLs[version]+oidcCallbackPath)
	}
	for provider, client := range map[string]fakeoidc.Client{fakeoidc.Google: b.Google, fakeoidc.GitHub: b.GitHub} {
		client.RedirectURIs = redirects
		if err := c.admin(ctx, http.MethodPut, oidcURL+"/_compat/clients/"+provider,
			"application/x-www-form-urlencoded", client.Form().Encode()); err != nil {
			return nil, err
		}
	}
	return c, nil
}

// seededTables は、public の表のうち、行のある表の名前を返す。
func seededTables(ctx context.Context, connString string) (map[string]bool, error) {
	conn, err := pgx.Connect(ctx, connString)
	if err != nil {
		return nil, fmt.Errorf("harness: データベースにつなげません: %w", err)
	}
	defer func() { _ = conn.Close(context.Background()) }()
	tables, err := publicTables(ctx, conn)
	if err != nil {
		return nil, err
	}
	seeded := map[string]bool{}
	for _, table := range tables {
		var has bool
		if err := conn.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM "+pgx.Identifier{table}.Sanitize()+")").Scan(&has); err != nil {
			return nil, fmt.Errorf("harness: 表 %s の行を数えられません: %w", table, err)
		}
		if has {
			seeded[table] = true
		}
	}
	return seeded, nil
}

// publicTables は、public の表のうち、表の形の履歴の表を除いた名前を返す。
func publicTables(ctx context.Context, conn *pgx.Conn) ([]string, error) {
	rows, err := conn.Query(ctx, `SELECT table_name::text FROM information_schema.tables
		WHERE table_schema = 'public' AND table_type = 'BASE TABLE' AND table_name <> $1 ORDER BY 1`, historyTable)
	if err != nil {
		return nil, fmt.Errorf("harness: 表の一覧を読めません: %w", err)
	}
	tables, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return nil, fmt.Errorf("harness: 表の一覧を読めません: %w", err)
	}
	return tables, nil
}

// Reset は、送り先の組の前に、保存された内容を空にする。データベースは、表の形の履歴を適用した直後に行の無かった表を空にし、
// 履歴が入れた行(役割など)は残す。Redis はすべてのキーを消し、fakeaws は覚えたオブジェクトとメールを消す。
// fakeaws の秘密の値は残す。backend が起動のときに読んだ値と同じでなければならないためである。
func (c *CrossEnv) Reset(ctx context.Context) error {
	conn, err := pgx.Connect(ctx, c.DBConn)
	if err != nil {
		return fmt.Errorf("harness: データベースにつなげません: %w", err)
	}
	defer func() { _ = conn.Close(context.Background()) }()
	tables, err := publicTables(ctx, conn)
	if err != nil {
		return err
	}
	var names []string
	for _, table := range tables {
		if !c.seeded[table] {
			names = append(names, pgx.Identifier{table}.Sanitize())
		}
	}
	if len(names) > 0 {
		// 1つの文で空にするので、空にする表どうしの外部キーは止めない。残す表から空にする表への外部キーがあれば、失敗にする。
		if _, err := conn.Exec(ctx, "TRUNCATE "+strings.Join(names, ", ")); err != nil {
			return fmt.Errorf("harness: 表を空にできません: %w", err)
		}
	}
	if err := c.Redis.FlushAll(ctx).Err(); err != nil {
		return fmt.Errorf("harness: Redis を空にできません: %w", err)
	}
	return c.admin(ctx, http.MethodDelete, c.AWSURL+"/_compat/records", "", "")
}

// Run は、筋書き s を、3つの送り先の組で1つずつ動かす。組ごとに、保存された内容を空にしてから筋書きの初めのデータを読み込む。
// 環境を整えられないときは、誤りを返す。筋書きの段が期待に合わないときは、報告の Failures に書く。
func (c *CrossEnv) Run(ctx context.Context, s Scenario) (CrossReport, error) {
	report := CrossReport{Scenario: s.Name, Directions: CrossDirections}
	for _, direction := range CrossDirections {
		if err := c.Reset(ctx); err != nil {
			return report, err
		}
		if err := LoadFixtures(ctx, c.DBConn, s.Fixtures); err != nil {
			return report, err
		}
		if f := RunCross(ctx, c.client, s, direction, c.URLs); f != nil {
			report.Failures = append(report.Failures, *f)
		}
	}
	return report, nil
}

// Close は、Redis のクライアントを閉じる。コンテナは Env が片付ける。
func (c *CrossEnv) Close() error {
	if c.Redis == nil {
		return nil
	}
	return c.Redis.Close()
}

// admin は、fakeaws と fakeoidc の /_compat/ の口に要求を送り、2xx でなければ誤りを返す。
func (c *CrossEnv) admin(ctx context.Context, method, target, contentType, body string) error {
	req, err := http.NewRequestWithContext(ctx, method, target, strings.NewReader(body))
	if err != nil {
		return fmt.Errorf("harness: %s %s の要求を作れません: %w", method, target, err)
	}
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("harness: %s %s を送れません: %w", method, target, err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode/100 != 2 {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return errors.New("harness: " + method + " " + target + " が " + resp.Status + " で断られました: " + string(msg))
	}
	return nil
}
