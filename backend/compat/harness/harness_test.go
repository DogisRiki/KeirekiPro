//go:build compat

package harness

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	tcexec "github.com/testcontainers/testcontainers-go/exec"
	"github.com/testcontainers/testcontainers-go/wait"
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
