//go:build compat

package harness

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeoidc"
)

// modeTestJWTKey は、3つの動かし方のテストで、偽の版と harness が使う JWT.Secret の値である。
const modeTestJWTKey = "mode-test-jwt-key-0123456789abcdef"

// modeScenario は、oidc_users と、mail: の取り出しと、絶対の URL の段と、Redis を書き換える段と、
// 値を期限切れにする段を含む、3つの動かし方で動く筋書きである。
// 登録の段で、偽の版がメールで確認のリンクを送り、ログインの状態の値と続けるための値を Cookie で返す。
// 確かめる段で、偽の版は、リンクとログインの状態の値の期限が切れ、続けるための値が Redis から消え、
// marker が Redis にあるときだけ 410 を返す。
// 呼ばれた回数を返させる段は、偽のログインのサービスに、呼ばれた回数を本文で返させる。比べる動かし方では、Java 版の番と
// Go 版の番で本文が違うので、絶対の URL の段の応答を比べると違いになる。
const modeScenario = `name: 新しい段
modes: [compare, cross, perf]
prepare_each: true
oidc_users:
  google: {sub: g-a, name: A, email: a@example.com, email_verified: true}
steps:
  - name: 登録
    request: {method: POST, path: /register}
    capture: {link: "mail:verify#(\\S+)", rt: "cookie:refreshToken"}
    expect: {status: 200}
  - name: 利用者を替える
    request:
      method: PUT
      url: "http://fakeoidc:8080/_compat/users/google"
      json: {sub: g-b, name: B, email: b@example.com, email_verified: true}
    expect: {status: 204}
  - name: 続けるための値を消す
    redis:
      del: ["refresh-token:{rt}"]
      set:
        - {key: marker, value: '{"ok":true}', ttl_seconds: 600}
  - name: リンクの期限を切らす
    expire: {var: link}
  - name: ログインの期限を切らす
    expire: {cookie: accessToken}
  - name: 呼ばれた回数を返させる
    request: {method: GET, url: "http://fakeoidc:8080/count"}
    expect: {status: 200}
  - name: 確かめる
    to: other
    request: {method: POST, path: /verify, json: {token: "{link}"}}
    expect: {status: 410}
`

// startModeStores は、表の無い Postgres と、Valkey を動かし、Postgres のつなぎ先と Valkey のアドレスを返す。
func startModeStores(t *testing.T) (string, string) {
	t.Helper()
	ctx := t.Context()
	pg, err := postgres.Run(ctx, postgresImage,
		postgres.WithDatabase("keireki_pro"),
		postgres.WithUsername("postgres"),
		postgres.WithPassword("postgres"),
		postgres.BasicWaitStrategies(),
	)
	t.Cleanup(func() {
		if err := testcontainers.TerminateContainer(pg); err != nil {
			t.Errorf("Postgres のコンテナを止められません: %v", err)
		}
	})
	if err != nil {
		t.Fatalf("Postgres のコンテナを動かせません: %v", err)
	}
	dbConn, err := pg.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatalf("Postgres のつなぎ先を読めません: %v", err)
	}
	vk, err := testcontainers.Run(ctx, valkeyImage,
		testcontainers.WithExposedPorts("6379/tcp"),
		testcontainers.WithWaitStrategy(wait.ForListeningPort("6379/tcp")),
	)
	t.Cleanup(func() {
		if err := testcontainers.TerminateContainer(vk); err != nil {
			t.Errorf("Valkey のコンテナを止められません: %v", err)
		}
	})
	if err != nil {
		t.Fatalf("Valkey のコンテナを動かせません: %v", err)
	}
	addr, err := vk.PortEndpoint(ctx, "6379/tcp", "")
	if err != nil {
		t.Fatalf("Valkey のつなぎ先を読めません: %v", err)
	}
	return dbConn, addr
}

// modeStore は、Postgres の dbConn と、Valkey の addr のデータベースの番号 db につないだ Store を作る。
// 版ごとの Redis の代わりに、1つの Valkey の別々のデータベースを使う。
func modeStore(t *testing.T, dbConn, addr string, db int) *Store {
	t.Helper()
	c := redis.NewClient(&redis.Options{Addr: addr, DB: db})
	t.Cleanup(func() { _ = c.Close() })
	return &Store{DBConn: dbConn, Redis: c}
}

// oidcLog は、偽のログインのサービスが受けた /_compat/ の口の要求を、「メソッド パス 本文」の形で受けた順に覚える。
type oidcLog struct {
	mu    sync.Mutex
	calls []string
}

// take は、覚えた要求を返し、記録を空にする。
func (l *oidcLog) take() []string {
	l.mu.Lock()
	defer l.mu.Unlock()
	calls := l.calls
	l.calls = nil
	return calls
}

// startModeFakes は、偽の AWS と、受けた要求を記録する偽のログインのサービスを、テストの処理の中で動かす。
func startModeFakes(t *testing.T) (*fakes, *oidcLog) {
	t.Helper()
	aws := httptest.NewServer(fakeaws.NewServer())
	t.Cleanup(aws.Close)
	log := &oidcLog{}
	inner := fakeoidc.NewServer()
	var count atomic.Int64
	oidc := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/count" {
			w.Header().Set("Content-Type", "text/plain")
			_, _ = fmt.Fprintf(w, "%d", count.Add(1))
			return
		}
		if strings.HasPrefix(r.URL.Path, "/_compat/") {
			body, _ := io.ReadAll(r.Body)
			r.Body = io.NopCloser(bytes.NewReader(body))
			log.mu.Lock()
			log.calls = append(log.calls, r.Method+" "+r.URL.Path+" "+string(body))
			log.mu.Unlock()
		}
		inner.ServeHTTP(w, r)
	}))
	t.Cleanup(oidc.Close)
	return &fakes{AWSURL: aws.URL, oidcURL: oidc.URL, jwtSecret: modeTestJWTKey, client: aws.Client()}, log
}

// checkOIDCRound は、偽のログインのサービスの記録 calls が、筋書きの1回の実行の形かを確かめる。
// 初めの状態に戻し、oidc_users の利用者 A を登録し、利用者を替える段で B を changes 回受け、終わりに初めの状態に戻す形である。
func checkOIDCRound(t *testing.T, name string, calls []string, changes int) {
	t.Helper()
	isReset := func(c string) bool { return strings.HasPrefix(c, "POST /_compat/reset") }
	isUser := func(c, sub string) bool {
		return strings.HasPrefix(c, "PUT /_compat/users/google ") && strings.Contains(c, `"sub":"`+sub+`"`)
	}
	ok := len(calls) == changes+3 && isReset(calls[0]) && isUser(calls[1], "g-a") && isReset(calls[len(calls)-1])
	for i := 2; ok && i < len(calls)-1; i++ {
		ok = isUser(calls[i], "g-b")
	}
	if !ok {
		t.Errorf("%s: 偽のログインのサービスの記録 = %q, want 初めの状態に戻す、A を登録、B を %d 回、初めの状態に戻す", name, calls, changes)
	}
}

// modeIssued は、偽の版が最後に出した値と、確かめる段の結果である。版をまたぐ動かし方では、2つの偽の版が1つを共有する。
type modeIssued struct {
	mu      sync.Mutex
	linkJTI string
	rt      string
	// verified は、確かめる段の要求が、すべての確かめに合った回数である。
	verified int
	problems []string
}

// modeBackend は、3つの動かし方のテストで、版の代わりをする HTTP のサーバである。
type modeBackend struct {
	redis *redis.Client
	// awsURL と awsHost は、メールを送る偽の AWS のアドレスと、要求の Host である。Host で偽の AWS の版が決まる。
	awsURL, awsHost string
	issued          *modeIssued
	// delay は、登録の段で、リンクを作る前に待つ時間である。
	delay atomic.Int64
	// extraLexp は、確認のリンクの lexp に足す秒である。
	extraLexp atomic.Int64
}

func (b *modeBackend) start(t *testing.T) string {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("POST /register", b.register)
	mux.HandleFunc("POST /verify", b.verify)
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv.URL
}

func (b *modeBackend) register(w http.ResponseWriter, r *http.Request) {
	time.Sleep(time.Duration(b.delay.Load()))
	now := time.Now().Unix()
	access := modeJWT(fmt.Sprintf(`{"sub":"u1","iat":%d,"exp":%d,"jti":%q}`, now, now+600, modeUUID()), []byte(modeTestJWTKey))
	jti, rt := modeUUID(), modeUUID()
	link := modeJWT(fmt.Sprintf(`{"aud":"email-verification","sub":"u1","purpose":"verify","email":"a@example.com","lexp":%d,"jti":%q}`,
		now+86400+b.extraLexp.Load(), jti), emailVerificationTestKey(modeTestJWTKey))
	ctx := r.Context()
	// 期限を付けない。Go 版を遅らせる場合に、残りの有効な時間が版ごとにずれないようにする
	if err := b.redis.Set(ctx, "refresh-token:"+rt, `{"userId":"u1"}`, 0).Err(); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err := b.sendMail(ctx, "次のリンクを開いてください\nhttp://compat.test/email/verify#"+link); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	b.issued.mu.Lock()
	b.issued.linkJTI, b.issued.rt = jti, rt
	b.issued.mu.Unlock()
	for name, value := range map[string]string{"accessToken": access, "refreshToken": rt} {
		http.SetCookie(w, &http.Cookie{Name: name, Value: value, Path: "/", HttpOnly: true, Secure: true, SameSite: http.SameSiteLaxMode})
	}
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"ok":true}`))
}

func (b *modeBackend) sendMail(ctx context.Context, text string) error {
	form := url.Values{
		"Action":                           {"SendEmail"},
		"Source":                           {"no-reply@example.com"},
		"Destination.ToAddresses.member.1": {"a@example.com"},
		"Message.Subject.Data":             {"メールアドレスの確認"},
		"Message.Body.Text.Data":           {text},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, b.awsURL+"/", strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Host = b.awsHost
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("偽の AWS がメールを %s で断りました", resp.Status)
	}
	return nil
}

func (b *modeBackend) verify(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Token string `json:"token"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	now := time.Now().Unix()
	ctx := r.Context()
	b.issued.mu.Lock()
	defer b.issued.mu.Unlock()
	var problems []string
	link, err := modeClaims(body.Token, emailVerificationTestKey(modeTestJWTKey))
	switch {
	case err != nil:
		problems = append(problems, "リンクの値: "+err.Error())
	case link["jti"] != b.issued.linkJTI:
		problems = append(problems, "リンクの値が、この版の最後に出した値ではありません")
	case modeClaimInt(link["lexp"]) >= now:
		problems = append(problems, "リンクの期限が切れていません")
	}
	if c, err := r.Cookie("accessToken"); err != nil {
		problems = append(problems, "accessToken がありません")
	} else if access, err := modeClaims(c.Value, []byte(modeTestJWTKey)); err != nil {
		problems = append(problems, "accessToken: "+err.Error())
	} else if modeClaimInt(access["exp"]) >= now {
		problems = append(problems, "accessToken の期限が切れていません")
	}
	if n, err := b.redis.Exists(ctx, "refresh-token:"+b.issued.rt).Result(); err != nil || n != 0 {
		problems = append(problems, fmt.Sprintf("続けるための値が Redis から消えていません(%d, %v)", n, err))
	}
	if v, err := b.redis.Get(ctx, "marker").Result(); err != nil || v != `{"ok":true}` {
		problems = append(problems, fmt.Sprintf("Redis の marker が %q です(%v)", v, err))
	}
	w.Header().Set("Content-Type", "application/json")
	if len(problems) > 0 {
		b.issued.problems = append(b.issued.problems, problems...)
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string][]string{"problems": problems})
		return
	}
	b.issued.verified++
	w.WriteHeader(http.StatusGone)
	_, _ = w.Write([]byte(`{"result":"expired"}`))
}

// result は、確かめる段の要求がすべての確かめに合った回数と、合わなかったことを返す。
func (i *modeIssued) result() (int, []string) {
	i.mu.Lock()
	defer i.mu.Unlock()
	return i.verified, slices.Clone(i.problems)
}

// modeJWT は、本体 payload を鍵 key の HS256 で署名した JWT を返す。
func modeJWT(payload string, key []byte) string {
	enc := base64.RawURLEncoding
	signing := enc.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`)) + "." + enc.EncodeToString([]byte(payload))
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(signing))
	return signing + "." + enc.EncodeToString(mac.Sum(nil))
}

// modeClaims は、JWT の値 token の署名を鍵 key で確かめ、本体の項目を返す。数は json.Number で返す。
func modeClaims(token string, key []byte) (map[string]any, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return nil, errors.New("JWT の形ではありません")
	}
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(parts[0] + "." + parts[1]))
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || !hmac.Equal(sig, mac.Sum(nil)) {
		return nil, errors.New("署名が合いません")
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, err
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	claims := map[string]any{}
	if err := dec.Decode(&claims); err != nil {
		return nil, err
	}
	return claims, nil
}

// modeClaimInt は、JWT の項目の数を返す。数でなければ0を返す。
func modeClaimInt(v any) int64 {
	n, ok := v.(json.Number)
	if !ok {
		return 0
	}
	i, _ := n.Int64()
	return i
}

// modeUUID は、乱数の UUID(版4)を返す。
func modeUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

func loadModeScenario(t *testing.T) Scenario {
	t.Helper()
	s, err := LoadScenario(writeScenario(t, modeScenario))
	if err != nil {
		t.Fatalf("筋書きを読めません: %v", err)
	}
	return s
}

func TestCompareEnv_NewSteps(t *testing.T) {
	s := loadModeScenario(t)
	dbConn, addr := startModeStores(t)
	f, log := startModeFakes(t)
	c := &CompareEnv{Stores: map[string]*Store{}, URLs: map[string]string{}, fakes: f, client: NewHTTPClient()}
	backends := map[string]*modeBackend{}
	for i, version := range []string{VersionJava, VersionGo} {
		c.Stores[version] = modeStore(t, dbConn, addr, i)
		// 版ごとの偽の AWS の記録に送る
		backends[version] = &modeBackend{redis: c.Stores[version].Redis, awsURL: f.AWSURL, awsHost: awsHost(version), issued: &modeIssued{}}
		c.URLs[version] = backends[version].start(t)
	}

	t.Run("lexp を応答を受けた時刻との差で比べる", func(t *testing.T) {
		// Go 版は、許すずれより長く遅れてリンクを作る。lexp の時刻はずれるが、応答を受けた時刻との差は同じである
		backends[VersionGo].delay.Store(int64(RedisTTLTolerance + time.Second))
		defer backends[VersionGo].delay.Store(0)
		report, err := c.Run(t.Context(), s)
		if err != nil {
			t.Fatalf("Run: %v", err)
		}
		if report.Failed() {
			t.Errorf("違いがあります:\n%s", report)
		}
		for version, b := range backends {
			if verified, problems := b.issued.result(); verified != 1 || len(problems) > 0 {
				t.Errorf("版 %s の確かめる段: 合った回数 %d, 合わなかったこと %q", version, verified, problems)
			}
		}
		// 利用者を替える段は、版ごとに1回ずつ送る
		checkOIDCRound(t, "比べる動かし方", log.take(), 2)
	})

	t.Run("lexp の差が違えば報告する", func(t *testing.T) {
		backends[VersionGo].extraLexp.Store(60)
		defer backends[VersionGo].extraLexp.Store(0)
		report, err := c.Run(t.Context(), s)
		if err != nil {
			t.Fatalf("Run: %v", err)
		}
		if len(report.Diffs) != 1 || report.Diffs[0].Target != TargetMail || report.Diffs[0].Step.Index != 1 {
			t.Errorf("違い = %+v, want 登録の段のメールの違いが1つ", report.Diffs)
		}
		checkOIDCRound(t, "比べる動かし方", log.take(), 2)
	})

	t.Run("段を動かせなくても初めの状態に戻す", func(t *testing.T) {
		broken := s
		broken.Steps = slices.Clone(s.Steps)
		broken.Steps[3].Expire = &ExpireStep{Var: "missing"}
		if _, err := c.Run(t.Context(), broken); err == nil || !strings.Contains(err.Error(), "missing") {
			t.Errorf("Run の誤り = %v, want 取り出していない値の名前を含む", err)
		}
		calls := log.take()
		if len(calls) == 0 || !strings.HasPrefix(calls[len(calls)-1], "POST /_compat/reset") {
			t.Errorf("偽のログインのサービスの記録 = %q, want 終わりに初めの状態に戻す", calls)
		}
	})

	t.Run("絶対の URL の段の status が期待と違えば誤りにする", func(t *testing.T) {
		broken := s
		broken.Steps = slices.Clone(s.Steps)
		broken.Steps[1].Expect.Status = http.StatusOK
		if _, err := c.Run(t.Context(), broken); err == nil || !strings.Contains(err.Error(), "ステータスが 204 でした。期待は 200 です") {
			t.Errorf("Run の誤り = %v, want 絶対の URL の段の status の違い", err)
		}
		calls := log.take()
		if len(calls) == 0 || !strings.HasPrefix(calls[len(calls)-1], "POST /_compat/reset") {
			t.Errorf("偽のログインのサービスの記録 = %q, want 終わりに初めの状態に戻す", calls)
		}
	})
}

func TestCrossEnv_NewSteps(t *testing.T) {
	s := loadModeScenario(t)
	dbConn, addr := startModeStores(t)
	f, log := startModeFakes(t)
	st := modeStore(t, dbConn, addr, 0)
	issued := &modeIssued{}
	c := &CrossEnv{Stack: &Stack{Store: st, fakes: f}, URLs: map[string]string{}, client: NewHTTPClient()}
	for _, version := range []string{VersionJava, VersionGo} {
		// 2つの版は、1つの Redis と、偽の AWS の共有の版に送る
		b := &modeBackend{redis: st.Redis, awsURL: f.AWSURL, awsHost: "fakeaws", issued: issued}
		c.URLs[version] = b.start(t)
	}
	report, err := c.Run(t.Context(), s)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if report.Failed() {
		t.Errorf("最後まで終わらなかった組があります:\n%s", report)
	}
	if verified, problems := issued.result(); verified != len(CrossDirections) || len(problems) > 0 {
		t.Errorf("確かめる段: 合った回数 %d, 合わなかったこと %q, want %d 回", verified, problems, len(CrossDirections))
	}
	// 向きごとに、初めの状態に戻して A を登録し直す。利用者を替える段は1回だけ送る
	calls := log.take()
	if len(calls) != 4*len(CrossDirections) {
		t.Fatalf("偽のログインのサービスの記録 = %q, want 向きごとに4つ", calls)
	}
	for i, direction := range CrossDirections {
		checkOIDCRound(t, direction, calls[4*i:4*i+4], 1)
	}
}

func TestPerfEnv_NewSteps(t *testing.T) {
	s := loadModeScenario(t)
	dbConn, addr := startModeStores(t)
	envs := map[string]*PerfEnv{}
	logs := map[string]*oidcLog{}
	issued := map[string]*modeIssued{}
	for i, version := range []string{VersionJava, VersionGo} {
		// 版ごとの環境に、別々の偽の AWS と偽のログインのサービスがある
		f, log := startModeFakes(t)
		st := modeStore(t, dbConn, addr, i)
		issued[version] = &modeIssued{}
		b := &modeBackend{redis: st.Redis, awsURL: f.AWSURL, awsHost: "fakeaws", issued: issued[version]}
		envs[version] = &PerfEnv{Stack: &Stack{Store: st, fakes: f}, URL: b.start(t), client: NewHTTPClient()}
		logs[version] = log
	}
	opts := PerfOptions{Warmup: 1, Samples: 2, Concurrency: 2}
	report, err := RunPerf(t.Context(), envs, []Scenario{s}, opts)
	if err != nil {
		t.Fatalf("RunPerf: %v", err)
	}
	if len(report.Latencies) != 1 || report.Latencies[0].Java <= 0 || report.Latencies[0].Go <= 0 {
		t.Errorf("測った時間 = %+v", report.Latencies)
	}
	rounds := opts.Warmup + opts.Samples
	for _, version := range []string{VersionJava, VersionGo} {
		if verified, problems := issued[version].result(); verified != rounds || len(problems) > 0 {
			t.Errorf("版 %s の確かめる段: 合った回数 %d, 合わなかったこと %q, want %d 回", version, verified, problems, rounds)
		}
		// 準備の段を回ごとに送り直すので、利用者を替える段も回ごとに送る
		checkOIDCRound(t, "版 "+version+" の環境", logs[version].take(), rounds)
	}
}

func TestCrossRoute_OnlyVersionSteps(t *testing.T) {
	version := func(name, to string) Step {
		s := get(name, "/")
		s.To = to
		s.Expect.Status = http.StatusOK
		return s
	}
	absolute := Step{Name: "absolute", Request: Request{Method: http.MethodGet, URL: "http://fakeoidc:8080/x"}}
	redisStep := Step{Name: "redis", Redis: &RedisStep{Del: []string{"k"}}}
	expire := Step{Name: "expire", Expire: &ExpireStep{Var: "link"}}
	s := Scenario{Name: "s", Steps: []Step{
		version("v1", ""), absolute, version("v2", ToOther), redisStep, version("v3", ""), expire, version("v4", ""),
	}}
	j, g := VersionJava, VersionGo
	for direction, want := range map[string][]string{
		CrossJavaToGo: {j, "", g, "", g, "", j},
		CrossGoToJava: {g, "", j, "", j, "", g},
		// 版に送る段の数で交互にする。ほかの段をはさんでも、v1 から v4 は Java、Go、Java、Go になる
		CrossAlternate: {j, "", g, "", j, "", g},
	} {
		got, err := CrossRoute(s, direction)
		if err != nil || !slices.Equal(got, want) {
			t.Errorf("%s: CrossRoute = %q, %v, want %q", direction, got, err, want)
		}
	}
	for name, tc := range map[string]struct {
		steps []Step
		want  []string
	}{
		"版に送る段が1つ":      {[]Step{absolute, redisStep, version("v1", "")}, []string{"2つ以上", "1 段"}},
		"最後の段が版に送る段でない": {[]Step{version("v1", ""), version("v2", ""), expire}, []string{"最後の段", "expire"}},
	} {
		_, err := CrossRoute(Scenario{Name: "s", Steps: tc.steps}, CrossJavaToGo)
		for _, w := range tc.want {
			if err == nil || !strings.Contains(err.Error(), w) {
				t.Errorf("%s: 誤り = %v, want %q を含む", name, err, w)
			}
		}
	}
}

func TestRunCross_FailsOnOtherStepWithoutVersion(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) }))
	defer srv.Close()
	s := crossScenario("", "")
	s.Steps[0].Expect.Status = http.StatusOK
	s.Steps = slices.Insert(s.Steps, 1, Step{Name: "expire", Expire: &ExpireStep{Var: "missing"}})
	f := RunCross(t.Context(), srv.Client(), s, CrossJavaToGo, map[string]string{VersionJava: srv.URL, VersionGo: srv.URL})
	if f == nil || f.Step.Index != 2 || f.Step.Name != "expire" || f.Version != "" ||
		len(f.Problems) != 1 || !strings.Contains(f.Problems[0], "missing") {
		t.Errorf("版に送る段でない段の失敗 = %+v", f)
	}
}

func TestMeasureLatency_RedisStepWithoutRedisFails(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) }))
	defer srv.Close()
	s := perfScenario(http.StatusOK)
	s.Steps = slices.Insert(s.Steps, 0, Step{Name: "redis", Redis: &RedisStep{Del: []string{"k"}}})
	if _, err := MeasureLatency(t.Context(), NewHTTPClient(), srv.URL, s, 1, 1); err == nil || !strings.Contains(err.Error(), "Redis") {
		t.Errorf("Redis の無い測り方の誤り = %v", err)
	}
	s = perfScenario(http.StatusOK)
	s.Steps = append(s.Steps, Step{Name: "expire", Expire: &ExpireStep{Var: "link"}})
	if _, err := MeasureLatency(t.Context(), NewHTTPClient(), srv.URL, s, 1, 1); err == nil ||
		!strings.Contains(err.Error(), "最後の段 expire") {
		t.Errorf("最後の段が版に送る段でない測り方の誤り = %v", err)
	}
}

// 版に送る段でない段は、Request に操作の方法とパスを持っていても、操作を扱ったことにしない。
func TestMissingOperations_OnlyVersionSteps(t *testing.T) {
	ops := realOperations(t)
	auth := opsOfGroup(ops, GroupAuth)
	completed := []int{GroupAuth}
	for name, change := range map[string]func(*Step){
		"Redis":   func(s *Step) { s.Redis = &RedisStep{Del: []string{"k"}} },
		"expire":  func(s *Step) { s.Expire = &ExpireStep{Var: "link"} },
		"絶対の URL": func(s *Step) { s.Request.URL = "http://fakeoidc:8080" + s.Request.Path },
	} {
		s := scenarioOf("auth", GroupAuth, auth...)
		change(&s.Steps[0])
		if got := ids(MissingOperations(ops, []Scenario{s}, completed, false)); !slices.Equal(got, []string{auth[0].ID}) {
			t.Errorf("%s: 足りない操作 = %v, want [%s]", name, got, auth[0].ID)
		}
	}
}

// 版をまたぐ動かし方と測る動かし方は、絶対の URL の段の応答の status を、expect の status と比べる。
func TestAbsoluteStep_StatusChecked(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) }))
	defer srv.Close()
	absolute := Step{
		Name:    "absolute",
		Request: Request{Method: http.MethodGet, URL: "http://fakeoidc:8080/x"},
		Expect:  Expect{Status: http.StatusNoContent},
	}
	tools := stepTools{client: srv.Client(), oidcURL: srv.URL}
	want := "ステータスが 200 でした。期待は 204 です"

	s := crossScenario("", "")
	s.Steps[0].Expect.Status = http.StatusOK
	s.Steps = slices.Insert(s.Steps, 1, absolute)
	f := runCross(t.Context(), tools, s, CrossJavaToGo, map[string]string{VersionJava: srv.URL, VersionGo: srv.URL})
	if f == nil || f.Step.Index != 2 || f.Version != "" || len(f.Problems) == 0 || !strings.Contains(f.Problems[0], want) {
		t.Errorf("版をまたぐ動かし方の失敗 = %+v, want 段 2 の status の違い", f)
	}
	// 絶対の URL の段の status の違いは SendAbsolute が書くので、CheckExpect で同じ違いを重ねて書かない
	if f != nil && strings.Count(strings.Join(f.Problems, "\n"), want) != 1 {
		t.Errorf("版をまたぐ動かし方の失敗の理由 = %q, want status の違いを1回だけ", f.Problems)
	}

	p := perfScenario(http.StatusOK)
	p.Steps = slices.Insert(p.Steps, 1, absolute)
	if _, err := measureLatency(t.Context(), tools, srv.URL, p, 1, 1); err == nil || !strings.Contains(err.Error(), want) {
		t.Errorf("測る動かし方の誤り = %v, want status の違い", err)
	}
}

// userFieldsScenario は、画像を multipart で上げる段と、版が返す署名付きの形の URL から画像を読む絶対の URL の段と、
// 上げた画像の値を expect.values で確かめる段を持つ、3つの動かし方で動く筋書きである。
const userFieldsScenario = `name: 利用者の欄
modes: [compare, cross, perf]
steps:
  - name: 画像を上げる
    request:
      method: POST
      path: /image
      multipart:
        - {name: file, file: profile.png, filename: me.png, content_type: image/png}
    capture: {url: "$.url"}
    expect: {status: 200}
  - name: 画像を読む
    request: {method: GET, url: "{url}"}
    expect: {status: 200, content_type: image/png, body_file: profile.png}
  - name: 値を確かめる
    to: other
    request: {method: GET, path: /image}
    expect:
      status: 200
      values: {"$.name": me.png, "$.url": "{url}"}
`

// userFieldsObject は、利用者の欄のテストで、偽の版が画像を置く置き場所の中の画像の名前である。
const userFieldsObject = "images/profile/me.png"

// userImage は、偽の版が最後に上げられた画像の名前と URL である。版をまたぐ動かし方では、2つの偽の版が1つを共有する。
type userImage struct {
	mu        sync.Mutex
	name, url string
}

// userFieldsBackend は、利用者の欄のテストで、版の代わりをする HTTP のサーバである。上げられた画像を偽の AWS に置き、
// ホストが localhost:4566 の、署名付きの形の URL を返す。署名の値と日時は、要求ごとに変わる。
type userFieldsBackend struct {
	// awsURL と awsHost は、画像を置く偽の AWS のアドレスと、要求の Host である。Host で偽の AWS の版が決まる。
	awsURL, awsHost string
	image           *userImage
	// replace は、nil でなければ、上げられた画像の代わりに偽の AWS に置くバイトである。
	replace []byte
}

func (b *userFieldsBackend) start(t *testing.T) string {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("POST /image", b.upload)
	mux.HandleFunc("GET /image", b.show)
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv.URL
}

func (b *userFieldsBackend) upload(w http.ResponseWriter, r *http.Request) {
	file, header, err := r.FormFile("file")
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	defer func() { _ = file.Close() }()
	body, err := io.ReadAll(file)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if b.replace != nil {
		body = b.replace
	}
	req, err := http.NewRequestWithContext(r.Context(), http.MethodPut, b.awsURL+"/keirekipro/"+userFieldsObject, bytes.NewReader(body))
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	req.Host = b.awsHost
	req.Header.Set("Content-Type", header.Header.Get("Content-Type"))
	req.Header.Set("X-Amz-Meta-Original-Name", header.Filename)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		http.Error(w, "偽の AWS が画像を "+resp.Status+" で断りました", http.StatusInternalServerError)
		return
	}
	now := time.Now().UTC()
	signed := "http://localhost:4566/keirekipro/" + userFieldsObject + "?X-Amz-Algorithm=AWS4-HMAC-SHA256" +
		"&X-Amz-Date=" + now.Format("20060102T150405Z") + "&X-Amz-SignedHeaders=host&X-Amz-Expires=300" +
		"&X-Amz-Credential=test%2F" + now.Format("20060102") + "%2Fap-northeast-1%2Fs3%2Faws4_request" +
		"&X-Amz-Signature=" + rand.Text()
	b.image.mu.Lock()
	b.image.name, b.image.url = header.Filename, signed
	b.image.mu.Unlock()
	b.writeImage(w)
}

func (b *userFieldsBackend) show(w http.ResponseWriter, _ *http.Request) {
	b.writeImage(w)
}

// writeImage は、最後に上げられた画像の名前と URL を JSON で返す。
func (b *userFieldsBackend) writeImage(w http.ResponseWriter) {
	b.image.mu.Lock()
	body := map[string]string{"name": b.image.name, "url": b.image.url}
	b.image.mu.Unlock()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(body)
}

func loadUserFieldsScenario(t *testing.T) Scenario {
	t.Helper()
	s, err := LoadScenario(writeScenario(t, userFieldsScenario))
	if err != nil {
		t.Fatalf("筋書きを読めません: %v", err)
	}
	return s
}

// withValues は、筋書き s の段 index の expect.values を values にした写しを返す。s は変えない。
func withValues(s Scenario, index int, values map[string]any) Scenario {
	s.Steps = slices.Clone(s.Steps)
	s.Steps[index].Expect.Values = values
	return s
}

// sharedAWSEndpoint は、版をまたぐ動かし方と応答の時間の比べ方で、版がつなぐ偽の AWS の接続先である。
var sharedAWSEndpoint = "http://fakeaws:" + fakeaws.Port

func TestCompareEnv_UserFields(t *testing.T) {
	s := loadUserFieldsScenario(t)
	dbConn, addr := startModeStores(t)
	f, _ := startModeFakes(t)
	c := &CompareEnv{Stores: map[string]*Store{}, URLs: map[string]string{}, fakes: f, client: NewHTTPClient()}
	backends := map[string]*userFieldsBackend{}
	for i, version := range []string{VersionJava, VersionGo} {
		c.Stores[version] = modeStore(t, dbConn, addr, i)
		// 版ごとの偽の AWS の記録に置く
		backends[version] = &userFieldsBackend{awsURL: f.AWSURL, awsHost: awsHost(version), image: &userImage{}}
		c.URLs[version] = backends[version].start(t)
	}

	t.Run("版ごとの接続先から画像を読み、署名の値を正規化して比べる", func(t *testing.T) {
		report, err := c.Run(t.Context(), s)
		if err != nil {
			t.Fatalf("Run: %v", err)
		}
		if report.Failed() {
			t.Errorf("違いがあります:\n%s", report)
		}
	})

	t.Run("版の画像は、その版の接続先を Host にして読む", func(t *testing.T) {
		// Go 版だけが別の画像を置く。Java 版の接続先で読むと、Go 版の画像の違いを見落とす
		gif, err := readImageFixture("profile.gif")
		if err != nil {
			t.Fatal(err)
		}
		backends[VersionGo].replace = gif
		defer func() { backends[VersionGo].replace = nil }()
		_, err = c.Run(t.Context(), s)
		if err == nil || !strings.Contains(err.Error(), "を版 go で送れません") || !strings.Contains(err.Error(), "期待は fixtures/images/profile.png の") {
			t.Errorf("Run の誤り = %v, want 版 go の画像を読む段の本文の違い", err)
		}
	})
}

func TestCrossEnv_UserFields(t *testing.T) {
	s := loadUserFieldsScenario(t)
	dbConn, addr := startModeStores(t)
	f, _ := startModeFakes(t)
	st := modeStore(t, dbConn, addr, 0)
	image := &userImage{}
	stack := &Stack{Store: st, fakes: f, backing: Backing{AWSEndpoint: sharedAWSEndpoint}}
	c := &CrossEnv{Stack: stack, URLs: map[string]string{}, client: NewHTTPClient()}
	for _, version := range []string{VersionJava, VersionGo} {
		// 2つの版は、1つの画像の記録と、偽の AWS の共有の版に置く
		b := &userFieldsBackend{awsURL: f.AWSURL, awsHost: "fakeaws", image: image}
		c.URLs[version] = b.start(t)
	}

	t.Run("送り先の版の応答で画像と値を確かめる", func(t *testing.T) {
		report, err := c.Run(t.Context(), s)
		if err != nil {
			t.Fatalf("Run: %v", err)
		}
		if report.Failed() {
			t.Errorf("最後まで終わらなかった組があります:\n%s", report)
		}
	})

	t.Run("値が違えば、送り先の版の段の失敗にする", func(t *testing.T) {
		broken := withValues(s, 2, map[string]any{"$.name": "other.png"})
		report, err := c.Run(t.Context(), broken)
		if err != nil {
			t.Fatalf("Run: %v", err)
		}
		if len(report.Failures) != len(CrossDirections) {
			t.Fatalf("失敗 = %+v, want 組ごとに1つ", report.Failures)
		}
		want := `段 値を確かめる の $.name の値が "me.png" でした。期待は "other.png" です`
		for _, failure := range report.Failures {
			route, err := CrossRoute(broken, failure.Direction)
			if err != nil {
				t.Fatal(err)
			}
			if failure.Step.Index != 3 || failure.Version != route[2] || len(failure.Problems) == 0 || failure.Problems[0] != want {
				t.Errorf("組 %s の失敗 = %+v, want 段 3 を版 %s に送った値の違い %q", failure.Direction, failure, route[2], want)
			}
		}
	})
}

func TestPerfEnv_UserFields(t *testing.T) {
	s := loadUserFieldsScenario(t)
	dbConn, addr := startModeStores(t)
	envs := map[string]*PerfEnv{}
	for i, version := range []string{VersionJava, VersionGo} {
		// 版ごとの環境に、別々の偽の AWS がある
		f, _ := startModeFakes(t)
		st := modeStore(t, dbConn, addr, i)
		b := &userFieldsBackend{awsURL: f.AWSURL, awsHost: "fakeaws", image: &userImage{}}
		stack := &Stack{Store: st, fakes: f, backing: Backing{AWSEndpoint: sharedAWSEndpoint}}
		envs[version] = &PerfEnv{Stack: stack, URL: b.start(t), client: NewHTTPClient()}
	}
	opts := PerfOptions{Warmup: 1, Samples: 2, Concurrency: 2}

	t.Run("準備の段で画像を上げて読み、最後の段の値を確かめて測る", func(t *testing.T) {
		report, err := RunPerf(t.Context(), envs, []Scenario{s}, opts)
		if err != nil {
			t.Fatalf("RunPerf: %v", err)
		}
		if len(report.Latencies) != 1 || report.Latencies[0].Java <= 0 || report.Latencies[0].Go <= 0 {
			t.Errorf("測った時間 = %+v", report.Latencies)
		}
	})

	t.Run("最後の段の値が違えば誤りにする", func(t *testing.T) {
		broken := withValues(s, 2, map[string]any{"$.name": "other.png"})
		want := `段 値を確かめる の $.name の値が "me.png" でした。期待は "other.png" です`
		if _, err := RunPerf(t.Context(), envs, []Scenario{broken}, opts); err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("RunPerf の誤り = %v, want 最後の段の値の違い", err)
		}
		// 慣らしの回を送らずに測る回だけを送っても、測った回の応答の値を確かめる
		java := envs[VersionJava]
		if _, err := measureLatency(t.Context(), java.stepTools(), java.URL, broken, 0, 1); err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("測る回の誤り = %v, want 最後の段の値の違い", err)
		}
	})

	t.Run("準備の段の値が違えば誤りにする", func(t *testing.T) {
		broken := withValues(s, 0, map[string]any{"$.name": "other.png"})
		_, err := RunPerf(t.Context(), envs, []Scenario{broken}, opts)
		if err == nil || !strings.Contains(err.Error(), `段 画像を上げる の $.name の値が "me.png" でした。期待は "other.png" です`) {
			t.Errorf("RunPerf の誤り = %v, want 準備の段の値の違い", err)
		}
	})
}
