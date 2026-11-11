//go:build compat

package harness

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/redis/go-redis/v9"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeoidc"
)

// backend がつなぐ Postgres と Redis の値である。backend は、ネットワークの中の名前でつなぐ。
const (
	crossDBName     = "keireki_pro"
	crossDBUser     = "postgres"
	crossDBPassword = "postgres"
	backendPort     = "8080/tcp"
	// oidcCallbackPath は、外部のログインの提供元が利用者を戻す、backend の口のパスである。
	oidcCallbackPath = "/api/auth/oidc/callback"
)

// Backend は、1つの版の位置に置く backend のイメージと、その起動の仕方である。
type Backend struct {
	Image string
	// Env は、つなぐ先から、コンテナの環境変数を作る。
	Env func(Backing) map[string]string
	// HealthPath は、起動を待つときに 200 を待つパスである。
	HealthPath string
	// MeasureStartup が true なら、起動から /healthz が 200 を返すまでの時間を測り、GoStartupLimit を超えたら起動を失敗にする。
	// Go 版の本番のイメージを置くときに true にする。
	MeasureStartup bool
}

// JavaBackend は、Java 版のイメージを、Java 版の起動の仕方で置く。
func JavaBackend(image string) Backend {
	return Backend{Image: image, Env: JavaEnv, HealthPath: "/actuator/health"}
}

// GoBackend は、Go 版のイメージを、Go 版の起動の仕方で置く。
// 検査の土台を確かめるときは、Java 版の位置にも Go 版のイメージを置く。
func GoBackend(image string) Backend {
	return Backend{Image: image, Env: GoEnv, HealthPath: "/healthz", MeasureStartup: true}
}

// Store は、1つの版がつなぐ、1つの Postgres と1つの Redis である。
type Store struct {
	// DBConn は、テストの処理から Postgres につなぐ接続の文字である。
	DBConn string
	// Redis は、テストの処理から Redis につなぐクライアントである。
	Redis *redis.Client

	// dbHost と redisHost は、ネットワークの中で backend が Postgres と Redis を呼ぶ名前である。
	dbHost, redisHost string
	// seeded は、表の形の履歴を適用した直後に行のあった表である。reset は、この表の行を残す。
	seeded map[string]bool
}

// startStore は、env のネットワークに、postgres<suffix> と redis<suffix> の名前で Postgres と Redis を起動し、
// 表の形の履歴を適用する。表の形の履歴は、backend を起動する前に適用する。Go 版は起動のときに履歴を確かめるだけで、
// 表を作らないためである。途中で失敗したときは、作った Redis のクライアントを閉じて誤りを返す。コンテナは env が片付ける。
func startStore(ctx context.Context, env *Env, images Images, suffix string) (*Store, error) {
	st := &Store{dbHost: "postgres" + suffix, redisHost: "redis" + suffix}
	if err := st.start(ctx, env, images); err != nil {
		_ = st.Close()
		return nil, err
	}
	return st, nil
}

func (st *Store) start(ctx context.Context, env *Env, images Images) error {
	pg, err := env.Start(ctx, ContainerSpec{
		Name:  st.dbHost,
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
		return err
	}
	rd, err := env.Start(ctx, ContainerSpec{
		Name:         st.redisHost,
		Image:        images[ImageRedis],
		ExposedPorts: []string{"6379/tcp"},
		WaitingFor:   wait.ForLog("Ready to accept connections"),
	})
	if err != nil {
		return err
	}
	dbEndpoint, err := pg.PortEndpoint(ctx, "5432/tcp", "")
	if err != nil {
		return fmt.Errorf("harness: Postgres の宛先を読めません: %w", err)
	}
	st.DBConn = "postgres://" + crossDBUser + ":" + crossDBPassword + "@" + dbEndpoint + "/" + crossDBName + "?sslmode=disable"
	if _, err := ApplyMigrations(ctx, st.DBConn); err != nil {
		return err
	}
	if st.seeded, err = seededTables(ctx, st.DBConn); err != nil {
		return err
	}
	redisEndpoint, err := rd.PortEndpoint(ctx, "6379/tcp", "")
	if err != nil {
		return fmt.Errorf("harness: Redis の宛先を読めません: %w", err)
	}
	st.Redis = redis.NewClient(&redis.Options{Addr: redisEndpoint})
	return nil
}

// reset は、データベースの、表の形の履歴を適用した直後に行の無かった表を空にし、履歴が入れた行(役割など)は残す。
// Redis はすべてのキーを消す。
func (st *Store) reset(ctx context.Context) error {
	conn, err := pgx.Connect(ctx, st.DBConn)
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
		if !st.seeded[table] {
			names = append(names, pgx.Identifier{table}.Sanitize())
		}
	}
	if len(names) > 0 {
		// 1つの文で空にするので、空にする表どうしの外部キーは止めない。残す表から空にする表への外部キーがあれば、失敗にする。
		if _, err := conn.Exec(ctx, "TRUNCATE "+strings.Join(names, ", ")); err != nil {
			return fmt.Errorf("harness: 表を空にできません: %w", err)
		}
	}
	if err := st.Redis.FlushAll(ctx).Err(); err != nil {
		return fmt.Errorf("harness: Redis を空にできません: %w", err)
	}
	return nil
}

// Close は、Redis のクライアントを閉じる。コンテナは Env が片付ける。
func (st *Store) Close() error {
	if st == nil || st.Redis == nil {
		return nil
	}
	return st.Redis.Close()
}

// fakes は、fakeaws と fakeoidc と、backend が使う JWT の値と外部のログインのクライアントである。
type fakes struct {
	// AWSURL は、テストの処理から届く fakeaws の URL である。
	AWSURL string

	oidcURL   string
	jwtSecret string
	google    fakeoidc.Client
	github    fakeoidc.Client
	client    *http.Client
}

// startFakes は、env のネットワークに、fakeaws と fakeoidc を起動する。awsAliases は、fakeaws を呼ぶ別の名前である。
// fakeaws は、要求の宛先のホスト名 fakeaws-<版> で版を分けるので、版ごとに記録を分けるときは fakeaws-<版> を渡す。
func startFakes(ctx context.Context, env *Env, images Images, awsAliases ...string) (*fakes, error) {
	aws, err := env.Start(ctx, ContainerSpec{
		Name:         "fakeaws",
		Aliases:      awsAliases,
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
	f := &fakes{
		jwtSecret: rand.Text() + rand.Text(),
		google:    fakeoidc.Client{ID: "google-" + rand.Text(), Secret: rand.Text()},
		github:    fakeoidc.Client{ID: "github-" + rand.Text(), Secret: rand.Text()},
		client:    NewHTTPClient(),
	}
	if f.AWSURL, err = aws.BaseURL(ctx, fakeaws.Port+"/tcp"); err != nil {
		return nil, err
	}
	if f.oidcURL, err = oidc.BaseURL(ctx, fakeoidc.Port+"/tcp"); err != nil {
		return nil, err
	}
	return f, nil
}

// backingFor は、st の Postgres と Redis と、ネットワークの中の名前 awsHost の fakeaws につなぐ、版のつなぐ先を返す。
// どの版も、同じ JWT の値と同じ外部のログインのクライアントを使う。
func (f *fakes) backingFor(st *Store, awsHost string) Backing {
	return Backing{
		DBHost: st.dbHost, DBPort: "5432", DBName: crossDBName, DBUser: crossDBUser, DBPassword: crossDBPassword,
		RedisHost: st.redisHost, RedisPort: "6379",
		JWTSecret:   f.jwtSecret,
		AWSEndpoint: "http://" + awsHost + ":" + fakeaws.Port,
		OIDCBaseURL: "http://fakeoidc:" + fakeoidc.Port,
		Google:      f.google,
		GitHub:      f.github,
	}
}

// clearRecords は、fakeaws が覚えたオブジェクトとメールを、すべての版について消す。
// 秘密の値は残す。backend が起動のときに読んだ値と同じでなければならないためである。
func (f *fakes) clearRecords(ctx context.Context) error {
	return f.admin(ctx, http.MethodDelete, f.AWSURL+"/_compat/records", "", "")
}

// records は、fakeaws が版 version について覚えた kind(objects か emails)を、JSON から v に読む。
func (f *fakes) records(ctx context.Context, version, kind string, v any) error {
	target := f.AWSURL + "/_compat/" + url.PathEscape(version) + "/" + kind
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return fmt.Errorf("harness: GET %s の要求を作れません: %w", target, err)
	}
	resp, err := f.client.Do(req)
	if err != nil {
		return fmt.Errorf("harness: GET %s を送れません: %w", target, err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return errors.New("harness: GET " + target + " が " + resp.Status + " で断られました: " + string(msg))
	}
	if err := json.NewDecoder(resp.Body).Decode(v); err != nil {
		return fmt.Errorf("harness: GET %s の応答を読めません: %w", target, err)
	}
	return nil
}

// Stack は、backend がつなぐ、1つの Postgres と1つの Redis と1つの fakeaws と1つの fakeoidc である。
// 版をまたぐ確認と応答の時間の比べ方が使う。
type Stack struct {
	*Store
	*fakes

	backing Backing
}

// startStack は、env のネットワークに、Postgres と Redis と fakeaws と fakeoidc を起動し、表の形の履歴を適用する。
// backend が読む秘密の値は、fakeaws の共有の版に登録する。
// 途中で失敗したときは、作った Redis のクライアントを閉じて誤りを返す。コンテナは env が片付ける。
func startStack(ctx context.Context, env *Env, images Images) (*Stack, error) {
	st, err := startStore(ctx, env, images, "")
	if err != nil {
		return nil, err
	}
	f, err := startFakes(ctx, env, images)
	if err != nil {
		_ = st.Close()
		return nil, err
	}
	s := &Stack{Store: st, fakes: f, backing: f.backingFor(st, "fakeaws")}
	// JavaSecrets は GoSecrets を含むので、どちらの版が読む秘密の値も、共有の版に1度に登録する。
	if err := RegisterSecrets(ctx, f.client, f.AWSURL, fakeaws.SharedVersion, JavaSecrets(s.backing)); err != nil {
		_ = st.Close()
		return nil, err
	}
	return s, nil
}

// startBackend は、env のネットワークに、backend-<version> の名前で、つなぐ先 b の be を起動し、
// 起動したコンテナと、テストの処理から届く URL と、起動の時間を返す。
// be.MeasureStartup が true なら、起動から /healthz が 200 を返すまでの時間を測り、GoStartupLimit を超えたら失敗を返す。
// false なら、起動の時間を測らず、0 を返す。
func startBackend(ctx context.Context, env *Env, version string, be Backend, b Backing) (*Container, string, time.Duration, error) {
	spec := ContainerSpec{
		Name:         "backend-" + version,
		Image:        be.Image,
		Env:          be.Env(b),
		ExposedPorts: []string{backendPort},
		WaitingFor:   wait.ForHTTP(be.HealthPath).WithPort(backendPort),
	}
	var ctr *Container
	var startup time.Duration
	var err error
	if be.MeasureStartup {
		ctr, startup, err = env.StartGo(ctx, spec)
	} else {
		ctr, err = env.Start(ctx, spec)
	}
	if err != nil {
		return nil, "", 0, fmt.Errorf("harness: 版 %s の位置の backend を起動できません: %w", version, err)
	}
	u, err := ctr.BaseURL(ctx, backendPort)
	if err != nil {
		return nil, "", 0, err
	}
	return ctr, u, startup, nil
}

// registerRedirects は、backend の外部のログインの口 http://compat.test/api/auth/oidc/callback を、
// fakeoidc の転送してよい先に登録する。版に送るすべての要求の Host は CompatHost なので、Java 版と Go 版は、
// どちらもこの URL を戻り先にする。版ごとのポートの URL は登録しない。
func (f *fakes) registerRedirects(ctx context.Context) error {
	redirects := []string{"http://" + CompatHost + oidcCallbackPath}
	for provider, client := range map[string]fakeoidc.Client{fakeoidc.Google: f.google, fakeoidc.GitHub: f.github} {
		client.RedirectURIs = redirects
		if err := f.admin(ctx, http.MethodPut, f.oidcURL+"/_compat/clients/"+provider,
			"application/x-www-form-urlencoded", client.Form().Encode()); err != nil {
			return err
		}
	}
	return nil
}

// resetOIDC は、fakeoidc が覚えた利用者と、断る動きを消す。
func (f *fakes) resetOIDC(ctx context.Context) error {
	return f.admin(ctx, http.MethodPost, f.oidcURL+"/_compat/reset", "", "")
}

// withOIDC は、fakeoidc を初めの状態に戻して users を登録してから run を呼び、run が失敗したときも、
// 終わりに fakeoidc を初めの状態に戻す。筋書きが途中で替えた利用者や断る動きを、次の筋書きに残さないためである。
func (f *fakes) withOIDC(ctx context.Context, users *OIDCUsers, run func() error) (err error) {
	if err := f.resetOIDC(ctx); err != nil {
		return err
	}
	defer func() { err = errors.Join(err, f.resetOIDC(context.WithoutCancel(ctx))) }()
	if err := f.setOIDCUsers(ctx, users); err != nil {
		return err
	}
	return run()
}

// mailReader は、fakeaws が版 version について覚えたメールを読む部品を返す。
func (f *fakes) mailReader(version string) MailReader {
	return func(ctx context.Context) ([]fakeaws.Email, error) {
		var mails []fakeaws.Email
		if err := f.records(ctx, version, "emails", &mails); err != nil {
			return nil, err
		}
		return mails, nil
	}
}

// tools は、client で fakeoidc に送り、rdb を書き換え、fakeaws の版 version のメールを読む stepTools を返す。
func (f *fakes) tools(client *http.Client, rdb *redis.Client, version string) stepTools {
	return stepTools{client: client, oidcURL: f.oidcURL, jwtKey: f.jwtSecret, redis: rdb, mail: f.mailReader(version)}
}

// setOIDCUsers は、筋書きの oidc_users の利用者を、Google、GitHub の順に fakeoidc に登録する。users が nil なら何もしない。
func (f *fakes) setOIDCUsers(ctx context.Context, users *OIDCUsers) error {
	if users == nil {
		return nil
	}
	put := func(provider string, user any) error {
		b, err := json.Marshal(user)
		if err != nil {
			return fmt.Errorf("harness: %s の利用者を JSON にできません: %w", provider, err)
		}
		if err := f.admin(ctx, http.MethodPut, f.oidcURL+"/_compat/users/"+provider, "application/json", string(b)); err != nil {
			return fmt.Errorf("harness: %s の利用者を登録できません: %w", provider, err)
		}
		return nil
	}
	if users.Google != nil {
		if err := put(fakeoidc.Google, users.Google); err != nil {
			return err
		}
	}
	if users.GitHub != nil {
		if err := put(fakeoidc.GitHub, users.GitHub); err != nil {
			return err
		}
	}
	return nil
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

// Reset は、保存された内容を空にする。データベースは、表の形の履歴を適用した直後に行の無かった表を空にし、
// 履歴が入れた行(役割など)は残す。Redis はすべてのキーを消し、fakeaws は覚えたオブジェクトとメールを消す。
// fakeaws の秘密の値は残す。backend が起動のときに読んだ値と同じでなければならないためである。
func (s *Stack) Reset(ctx context.Context) error {
	if err := s.reset(ctx); err != nil {
		return err
	}
	return s.clearRecords(ctx)
}

// Close は、Redis のクライアントを閉じる。コンテナは Env が片付ける。
func (s *Stack) Close() error {
	if s == nil {
		return nil
	}
	return s.Store.Close()
}

// admin は、fakeaws と fakeoidc の /_compat/ の口に要求を送り、2xx でなければ誤りを返す。
func (f *fakes) admin(ctx context.Context, method, target, contentType, body string) error {
	req, err := http.NewRequestWithContext(ctx, method, target, strings.NewReader(body))
	if err != nil {
		return fmt.Errorf("harness: %s %s の要求を作れません: %w", method, target, err)
	}
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	resp, err := f.client.Do(req)
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
