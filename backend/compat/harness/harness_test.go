//go:build compat

package harness

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	tcexec "github.com/testcontainers/testcontainers-go/exec"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeoidc"
)

// writeScenario は、筋書きのファイルを一時のフォルダに書き、そのパスを返す。
func writeScenario(t *testing.T, content string) string {
	t.Helper()
	file := filepath.Join(t.TempDir(), "scenario.yaml")
	if err := os.WriteFile(file, []byte(content), 0o600); err != nil {
		t.Fatalf("筋書きを書けません: %v", err)
	}
	return file
}

// designScenario は、design.md の「筋書きのファイルの形」の例である。
const designScenario = `name: login-and-save-basic
group: 1
fixtures: [users/basic.sql]
modes: [compare, cross]
steps:
  - name: login
    request:
      method: POST
      path: /api/auth/login
      json: {email: user1@example.com, password: Passw0rd!}
    capture: {}
    expect: {status: 200}
  - name: save-basic
    to: other
    request:
      method: PUT
      path: /api/resumes/{resume1}/basic
      csrf: true
      json: {name: 新しい名前}
    expect: {status: 200}
`

func TestLoadScenario_ParsesSteps(t *testing.T) {
	s, err := LoadScenario(writeScenario(t, designScenario))
	if err != nil {
		t.Fatalf("LoadScenario: %v", err)
	}
	if s.Name != "login-and-save-basic" || s.Group != 1 {
		t.Errorf("name と group = %q %d, want login-and-save-basic 1", s.Name, s.Group)
	}
	if len(s.Fixtures) != 1 || s.Fixtures[0] != "users/basic.sql" {
		t.Errorf("fixtures = %v, want [users/basic.sql]", s.Fixtures)
	}
	if !s.HasMode(ModeCompare) || !s.HasMode(ModeCross) || s.HasMode(ModePerf) {
		t.Errorf("modes = %v, want [compare cross]", s.Modes)
	}
	if len(s.Steps) != 2 {
		t.Fatalf("段の数 = %d, want 2", len(s.Steps))
	}
	login, save := s.Steps[0], s.Steps[1]
	if login.Name != "login" || login.Request.Method != http.MethodPost || login.Request.Path != "/api/auth/login" ||
		login.Request.CSRF || login.To != "" || login.Expect.Status != http.StatusOK {
		t.Errorf("1つ目の段 = %+v", login)
	}
	body, ok := login.Request.JSON.(map[string]any)
	if !ok || body["email"] != "user1@example.com" || body["password"] != "Passw0rd!" {
		t.Errorf("1つ目の段の本文 = %#v", login.Request.JSON)
	}
	if save.Name != "save-basic" || save.To != ToOther || save.Request.Method != http.MethodPut ||
		save.Request.Path != "/api/resumes/{resume1}/basic" || !save.Request.CSRF || save.Expect.Status != http.StatusOK {
		t.Errorf("2つ目の段 = %+v", save)
	}
	if body, ok := save.Request.JSON.(map[string]any); !ok || body["name"] != "新しい名前" {
		t.Errorf("2つ目の段の本文 = %#v", save.Request.JSON)
	}
}

func TestLoadScenario_RejectsUnknownMode(t *testing.T) {
	file := writeScenario(t, strings.Replace(designScenario, "modes: [compare, cross]", "modes: [compare, load]", 1))
	_, err := LoadScenario(file)
	if err == nil {
		t.Fatal("LoadScenario が、決めていない動かし方 load を受け付けました")
	}
	if !strings.Contains(err.Error(), `"load"`) {
		t.Errorf("誤り = %v, want 動かし方 \"load\" を名指す誤り", err)
	}
}

func TestNetwork_ContainersResolveByName(t *testing.T) {
	root, err := RepoRoot()
	if err != nil {
		t.Fatal(err)
	}
	ctx := t.Context()
	var buildLog bytes.Buffer
	images, err := BuildImages(ctx, root, &buildLog, ImageRedis)
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
	for _, name := range []string{"redis-java", "redis-go"} {
		if _, err := env.Start(ctx, ContainerSpec{
			Name:         name,
			Image:        images[ImageRedis],
			ExposedPorts: []string{"6379/tcp"},
			WaitingFor:   wait.ForLog("Ready to accept connections"),
		}); err != nil {
			t.Fatal(err)
		}
	}

	ping := func(from, to string) (int, string) {
		t.Helper()
		var c *Container
		for _, ctr := range env.containers {
			if ctr.Name == from {
				c = ctr
			}
		}
		code, out, err := c.Exec(ctx, []string{"valkey-cli", "-h", to, "ping"}, tcexec.Multiplexed())
		if err != nil {
			t.Fatalf("%s の中で valkey-cli を動かせません: %v", from, err)
		}
		var b bytes.Buffer
		if _, err := b.ReadFrom(out); err != nil {
			t.Fatalf("valkey-cli の出力を読めません: %v", err)
		}
		return code, b.String()
	}
	for _, pair := range [][2]string{{"redis-go", "redis-java"}, {"redis-java", "redis-go"}} {
		if code, out := ping(pair[0], pair[1]); code != 0 || !strings.Contains(out, "PONG") {
			t.Errorf("%s から %s を名前で呼べません: 終了 %d, 出力 %q", pair[0], pair[1], code, out)
		}
	}
	// ネットワークに入れていない名前は呼べない
	if code, out := ping("redis-go", "fakeaws"); code == 0 && strings.Contains(out, "PONG") {
		t.Errorf("ネットワークに無い名前 fakeaws に届きました: 出力 %q", out)
	}

	// 失敗したときに残すログは、コンテナごとの <名前>.log に書く
	dir := t.TempDir()
	if err := env.SaveLogs(ctx, dir); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"redis-java", "redis-go"} {
		log, err := os.ReadFile(filepath.Clean(filepath.Join(dir, name+".log")))
		if err != nil || !strings.Contains(string(log), "Ready to accept connections") {
			t.Errorf("%s のログ = %q, %v, want 起動の行を含むログ", name, log, err)
		}
	}
}

// healthzServer は、/healthz に、初めの notReady 回は 503 を、その後は 200 を返すサーバである。
func healthzServer(t *testing.T, notReady int32) *httptest.Server {
	t.Helper()
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/healthz" {
			http.NotFound(w, r)
			return
		}
		if calls.Add(1) <= notReady {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestStartup_Over10sFails(t *testing.T) {
	srv := healthzServer(t, 2)
	// 起動を頼んでから 10秒と少しが過ぎた時点で、/healthz が 200 を返し始める場合
	startedAt := time.Now().Add(-GoStartupLimit - 50*time.Millisecond)
	elapsed, err := MeasureGoStartup(t.Context(), NewHTTPClient(), srv.URL, startedAt)
	if err == nil {
		t.Fatalf("起動に %s かかったのに、失敗になりませんでした", elapsed)
	}
	if elapsed <= GoStartupLimit {
		t.Errorf("測った時間 = %s, want %s を超える時間", elapsed, GoStartupLimit)
	}
}

func TestStartup_Within10sPasses(t *testing.T) {
	srv := healthzServer(t, 2)
	// 起動を頼んでから 9秒が過ぎた時点で、/healthz が 200 を返し始める場合
	startedAt := time.Now().Add(-9 * time.Second)
	elapsed, err := MeasureGoStartup(t.Context(), NewHTTPClient(), srv.URL, startedAt)
	if err != nil {
		t.Fatalf("MeasureGoStartup: %v", err)
	}
	if elapsed < 9*time.Second || elapsed > GoStartupLimit {
		t.Errorf("測った時間 = %s, want 9秒から %s の間", elapsed, GoStartupLimit)
	}
}

// oidcRecorder は、本物の偽のログインのサービスの前で、受けた管理の要求の method とパスと本文を記録する。
type oidcRecorder struct {
	mu   sync.Mutex
	reqs []string
}

func (o *oidcRecorder) server(t *testing.T) *httptest.Server {
	t.Helper()
	oidc := fakeoidc.NewServer()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/_compat/") {
			body, _ := io.ReadAll(r.Body)
			o.mu.Lock()
			o.reqs = append(o.reqs, r.Method+" "+r.URL.Path+" "+string(body))
			o.mu.Unlock()
			r.Body = io.NopCloser(bytes.NewReader(body))
		}
		oidc.ServeHTTP(w, r)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func (o *oidcRecorder) take() []string {
	o.mu.Lock()
	defer o.mu.Unlock()
	out := o.reqs
	o.reqs = nil
	return out
}

func TestOIDCUsers_ResetAndSet(t *testing.T) {
	rec := &oidcRecorder{}
	srv := rec.server(t)
	f := &fakes{oidcURL: srv.URL, client: srv.Client()}
	ctx := t.Context()

	if err := f.resetOIDC(ctx); err != nil {
		t.Fatal(err)
	}
	if got := rec.take(); !slices.Equal(got, []string{"POST /_compat/reset "}) {
		t.Errorf("初めに戻す要求 = %q", got)
	}

	// 書いた提供元にだけ登録する。偽のログインのサービスは、知らない項目を断るので、2xx は形が合うことも示す
	users := &OIDCUsers{
		Google: &OIDCGoogleUser{Sub: "g-sub", Name: "G", Email: "g@example.com", EmailVerified: true},
		GitHub: &OIDCGitHubUser{ID: 7, Login: "gh", Emails: []OIDCGitHubEmail{{Email: "gh@example.com", Primary: true, Verified: true}}},
	}
	if err := f.setOIDCUsers(ctx, &OIDCUsers{Google: users.Google}); err != nil {
		t.Fatal(err)
	}
	got := rec.take()
	if len(got) != 1 || !strings.HasPrefix(got[0], "PUT /_compat/users/google ") {
		t.Fatalf("Google だけの登録の要求 = %q", got)
	}
	var g fakeoidc.GoogleUser
	if err := json.Unmarshal([]byte(strings.TrimPrefix(got[0], "PUT /_compat/users/google ")), &g); err != nil {
		t.Fatal(err)
	}
	if want := (fakeoidc.GoogleUser{Sub: "g-sub", Name: "G", Email: "g@example.com", EmailVerified: true}); g != want {
		t.Errorf("Google の利用者 = %+v, want %+v", g, want)
	}
	if err := f.setOIDCUsers(ctx, users); err != nil {
		t.Fatal(err)
	}
	got = rec.take()
	if len(got) != 2 || !strings.HasPrefix(got[0], "PUT /_compat/users/google ") || !strings.HasPrefix(got[1], "PUT /_compat/users/github ") {
		t.Fatalf("両方の登録の要求 = %q", got)
	}
	var gh fakeoidc.GitHubUser
	if err := json.Unmarshal([]byte(strings.TrimPrefix(got[1], "PUT /_compat/users/github ")), &gh); err != nil {
		t.Fatal(err)
	}
	if want := (fakeoidc.GitHubUser{ID: 7, Login: "gh", Emails: []fakeoidc.GitHubEmail{{Email: "gh@example.com", Primary: true, Verified: true}}}); !reflect.DeepEqual(gh, want) {
		t.Errorf("GitHub の利用者 = %+v, want %+v", gh, want)
	}
	// 利用者の無い筋書きでは、何も送らない
	if err := f.setOIDCUsers(ctx, nil); err != nil {
		t.Fatal(err)
	}
	if got := rec.take(); len(got) != 0 {
		t.Errorf("利用者の無い筋書きの要求 = %q", got)
	}

	// 偽のログインのサービスが断れば、誤りにする
	refusing := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusInternalServerError) }))
	t.Cleanup(refusing.Close)
	bad := &fakes{oidcURL: refusing.URL, client: refusing.Client()}
	if err := bad.resetOIDC(ctx); err == nil {
		t.Error("断られた初めに戻す要求が誤りになりません")
	}
	if err := bad.setOIDCUsers(ctx, users); err == nil || !strings.Contains(err.Error(), "google") {
		t.Errorf("断られた登録の誤り = %v", err)
	}
	if err := bad.setOIDCUsers(ctx, &OIDCUsers{GitHub: users.GitHub}); err == nil || !strings.Contains(err.Error(), "github") {
		t.Errorf("断られた GitHub の登録の誤り = %v", err)
	}
}

func TestStack_RedirectURIIsCompatTest(t *testing.T) {
	rec := &oidcRecorder{}
	srv := rec.server(t)
	f := &fakes{
		oidcURL: srv.URL, client: srv.Client(),
		google: fakeoidc.Client{ID: "google-id", Secret: "x"},
		github: fakeoidc.Client{ID: "github-id", Secret: "x"},
	}
	ctx := t.Context()
	if err := f.registerRedirects(ctx); err != nil {
		t.Fatal(err)
	}
	if err := f.setOIDCUsers(ctx, &OIDCUsers{
		Google: &OIDCGoogleUser{Sub: "s", Email: "g@example.com", EmailVerified: true},
		GitHub: &OIDCGitHubUser{ID: 1, Login: "l"},
	}); err != nil {
		t.Fatal(err)
	}
	const callback = "http://compat.test/api/auth/oidc/callback"
	authorize := func(path, clientID, redirect string) (int, string) {
		t.Helper()
		q := url.Values{"client_id": {clientID}, "redirect_uri": {redirect}, "response_type": {"code"}, "state": {"st"}}
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL+path+"?"+q.Encode(), nil)
		if err != nil {
			t.Fatal(err)
		}
		resp, err := NewHTTPClient().Do(req)
		if err != nil {
			t.Fatal(err)
		}
		_ = resp.Body.Close()
		return resp.StatusCode, resp.Header.Get("Location")
	}
	// 2つの提供元とも、compat.test の戻り先を受け、版のポートの URL は受けない
	for path, id := range map[string]string{"/o/oauth2/v2/auth": "google-id", "/login/oauth/authorize": "github-id"} {
		status, location := authorize(path, id, callback)
		if status != http.StatusFound || !strings.HasPrefix(location, callback+"?") {
			t.Errorf("%s: 状態 = %d、Location = %q, want 302 で %s へ", path, status, location, callback)
		}
		if status, _ := authorize(path, id, "http://127.0.0.1:8080/api/auth/oidc/callback"); status != http.StatusBadRequest {
			t.Errorf("%s: 版のポートの戻り先の状態 = %d, want 400", path, status)
		}
	}
}
