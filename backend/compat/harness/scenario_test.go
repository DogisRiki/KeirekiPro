//go:build compat

package harness

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeoidc"
)

func TestLoadScenario_ReadsExpectFields(t *testing.T) {
	file := writeScenario(t, strings.Replace(designScenario, "    capture: {}\n    expect: {status: 200}",
		"    capture: {token: $.token}\n    expect: {status: 200, fields: [$.token, $.user.id]}", 1))
	s, err := LoadScenario(file)
	if err != nil {
		t.Fatalf("LoadScenario: %v", err)
	}
	if got := s.Steps[0].Expect.Fields; !slices.Equal(got, []string{"$.token", "$.user.id"}) {
		t.Errorf("fields = %v", got)
	}
	if got := s.Steps[0].Capture["token"]; got != "$.token" {
		t.Errorf("capture = %q", got)
	}
}

func TestLoadScenario_RejectsBadPathsAndCrossWithoutStatus(t *testing.T) {
	for name, tc := range map[string]struct {
		from, to string
		want     []string
	}{
		"capture の場所": {"    capture: {}\n", "    capture: {token: token}\n", []string{"capture token", `"token"`}},
		"fields の場所":  {"    expect: {status: 200}\n  - name: save", "    expect: {status: 200, fields: [x]}\n  - name: save", []string{"fields", `"x"`}},
		"status の無い段": {"      json: {name: 新しい名前}\n    expect: {status: 200}\n", "      json: {name: 新しい名前}\n", []string{"save-basic", "status"}},
	} {
		_, err := LoadScenario(writeScenario(t, strings.Replace(designScenario, tc.from, tc.to, 1)))
		if err == nil {
			t.Errorf("%s: 誤った筋書きを受け付けました", name)
			continue
		}
		for _, w := range tc.want {
			if !strings.Contains(err.Error(), w) {
				t.Errorf("%s: 誤り = %v, want %q を含む", name, err, w)
			}
		}
	}

	oneStep := designScenario[:strings.Index(designScenario, "  - name: save-basic")]
	if _, err := LoadScenario(writeScenario(t, oneStep)); err == nil || !strings.Contains(err.Error(), "2つ以上") {
		t.Errorf("1段の cross の筋書きの誤り = %v", err)
	}
	// cross で動かない筋書きは、1段でも status が無くてもよい
	compareOnly := strings.Replace(strings.Replace(oneStep, "modes: [compare, cross]", "modes: [compare]", 1), "    expect: {status: 200}\n", "", 1)
	if _, err := LoadScenario(writeScenario(t, compareOnly)); err != nil {
		t.Errorf("compare だけの筋書き: %v", err)
	}
}

func TestLoadScenarios_WalksFoldersAndFiltersMode(t *testing.T) {
	dir := t.TempDir()
	write := func(rel, content string) {
		t.Helper()
		file := filepath.Join(dir, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(file), 0o750); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(file, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write("2/b.yaml", strings.Replace(designScenario, "name: login-and-save-basic", "name: b", 1))
	write("1/a.yaml", strings.Replace(designScenario, "name: login-and-save-basic", "name: a", 1))
	write("1/c.yaml", strings.Replace(strings.Replace(designScenario, "name: login-and-save-basic", "name: c", 1), "modes: [compare, cross]", "modes: [compare]", 1))
	write("1/notes.md", "筋書きではない")

	got, err := LoadScenarios(dir, ModeCross)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, s := range got {
		names = append(names, s.Name)
	}
	if !slices.Equal(names, []string{"a", "b"}) {
		t.Errorf("cross の筋書き = %v, want [a b]", names)
	}
	if got, err := LoadScenarios(dir, ModeCompare); err != nil || len(got) != 3 {
		t.Errorf("compare の筋書き = %d 件, %v, want 3 件", len(got), err)
	}

	write("3/broken.yaml", "name: x\nunknown: 1\n")
	if _, err := LoadScenarios(dir, ModeCross); err == nil || !strings.Contains(err.Error(), "broken.yaml") {
		t.Errorf("読めない筋書きの誤り = %v", err)
	}
	if got, err := LoadScenarios(filepath.Join(dir, "none"), ModeCross); err != nil || len(got) != 0 {
		t.Errorf("無いフォルダ = %v, %v, want 空", got, err)
	}
	if filepath.Base(ScenariosDir()) != "scenarios" || filepath.Base(filepath.Dir(ScenariosDir())) != "compat" {
		t.Errorf("ScenariosDir = %s", ScenariosDir())
	}
}

// kindsScenario は、動かし方 modes で、段 steps を持つ筋書きの YAML を返す。
func kindsScenario(modes, steps string) string {
	return "name: kinds\nmodes: [" + modes + "]\nsteps:\n" + steps
}

// fourKindSteps は、4種類の段を1つずつ持ち、最後に版に送る段を置いた段の並びである。
const fourKindSteps = `  - name: send
    request: {method: POST, path: /api/auth/login, csrf: true}
    capture: {token: $.token}
    expect: {status: 200, fields: [$.token]}
  - name: absolute
    request:
      method: PUT
      url: "http://fakeoidc:8080/_compat/users/google"
      headers: {X-Test: "1"}
      json: {sub: s1}
    capture: {location: $.x}
    expect: {status: 204}
  - name: redis
    redis:
      del: ["refresh_token:{token}"]
      set:
        - {key: "2fa:{uid}", value: '{"code":"123456"}', ttl_seconds: 600}
  - name: expire-cookie
    expire: {cookie: accessToken}
  - name: expire-var
    expire: {var: link}
  - name: last
    to: other
    request: {method: GET, path: /api/users/me}
    expect: {status: 200}
`

func TestScenarioValidate_StepKinds(t *testing.T) {
	s, err := LoadScenario(writeScenario(t, kindsScenario("compare, cross", fourKindSteps)))
	if err != nil {
		t.Fatalf("4種類の段の筋書き: %v", err)
	}
	wantKinds := []StepKind{StepVersion, StepAbsoluteURL, StepRedis, StepExpire, StepExpire, StepVersion}
	for i, step := range s.Steps {
		if got := step.Kind(); got != wantKinds[i] {
			t.Errorf("段 %s の種類 = %v, want %v", step.Name, got, wantKinds[i])
		}
	}
	if got := s.Steps[1].Request.URL; got != "http://fakeoidc:8080/_compat/users/google" {
		t.Errorf("絶対の URL = %q", got)
	}
	wantRedis := &RedisStep{Del: []string{"refresh_token:{token}"}, Set: []RedisSet{{Key: "2fa:{uid}", Value: `{"code":"123456"}`, TTLSeconds: 600}}}
	if got := s.Steps[2].Redis; !reflect.DeepEqual(got, wantRedis) {
		t.Errorf("Redis を書き換える段 = %+v, want %+v", got, wantRedis)
	}
	if got := s.Steps[3].Expire; got == nil || *got != (ExpireStep{Cookie: "accessToken"}) {
		t.Errorf("Cookie を期限切れにする段 = %+v", got)
	}
	if got := s.Steps[4].Expire; got == nil || *got != (ExpireStep{Var: "link"}) {
		t.Errorf("取り出した値を期限切れにする段 = %+v", got)
	}

	for name, step := range map[string]string{
		"種類の欄が無い":                 "    expect: {status: 200}\n",
		"request と redis":         "    request: {method: GET, path: /x}\n    redis: {del: [k]}\n",
		"request と expire":        "    request: {method: GET, path: /x}\n    expire: {cookie: accessToken}\n",
		"redis と expire":          "    redis: {del: [k]}\n    expire: {cookie: accessToken}\n",
		"headers だけの request":     "    request: {headers: {X-Test: \"1\"}}\n    redis: {del: [k]}\n",
		"json だけの request":        "    request: {json: {a: 1}}\n    redis: {del: [k]}\n",
		"csrf だけの request":        "    request: {csrf: true}\n    expire: {var: link}\n",
		"スキームの無い url":             "    request: {method: GET, url: \"//fakeoidc:8080/x\"}\n",
		"redis の段の fields":        "    redis: {del: [k]}\n    expect: {fields: [$.x]}\n",
		"版に送る段の method が無い":       "    request: {path: /x}\n",
		"版に送る段の path が無い":         "    request: {method: GET}\n",
		"絶対の URL の段の method が無い":  "    request: {url: \"http://fakeoidc:8080/x\"}\n",
		"path と url":              "    request: {method: GET, path: /x, url: \"http://fakeoidc:8080/x\"}\n",
		"絶対でない url":               "    request: {method: GET, url: /x}\n",
		"ホストの無い url":              "    request: {method: GET, url: \"http:///x\"}\n",
		"絶対の URL の段の csrf":        "    request: {method: GET, url: \"http://fakeoidc:8080/x\", csrf: true}\n",
		"絶対の URL の段の to":          "    to: same\n    request: {method: GET, url: \"http://fakeoidc:8080/x\"}\n",
		"絶対の URL の段の fields":      "    request: {method: GET, url: \"http://fakeoidc:8080/x\"}\n    expect: {fields: [$.x]}\n",
		"空の redis":                "    redis: {}\n",
		"redis の set の key が無い":   "    redis: {set: [{value: \"1\", ttl_seconds: 60}]}\n",
		"redis の set の value が無い": "    redis: {set: [{key: k, ttl_seconds: 60}]}\n",
		"redis の set の時間が無い":      "    redis: {set: [{key: k, value: \"1\"}]}\n",
		"redis の set の時間が負":       "    redis: {set: [{key: k, value: \"1\", ttl_seconds: -1}]}\n",
		"redis の del の空のキー":       "    redis: {del: [\"\"]}\n",
		"redis の段の capture":       "    redis: {del: [k]}\n    capture: {x: $.x}\n",
		"redis の段の expect":        "    redis: {del: [k]}\n    expect: {status: 200}\n",
		"redis の段の to":            "    to: other\n    redis: {del: [k]}\n",
		"空の expire":               "    expire: {}\n",
		"expire の cookie と var":   "    expire: {cookie: accessToken, var: link}\n",
		"expire の段の capture":      "    expire: {var: link}\n    capture: {x: $.x}\n",
		"expire の段の expect":       "    expire: {var: link}\n    expect: {status: 200}\n",
		"expire の段の to":           "    to: other\n    expire: {var: link}\n",
	} {
		steps := "  - name: bad\n" + step + "  - name: last\n    request: {method: GET, path: /x}\n"
		_, err := LoadScenario(writeScenario(t, kindsScenario("compare", steps)))
		if err == nil || !strings.Contains(err.Error(), "段 bad ") {
			t.Errorf("%s: 誤り = %v, want 段 bad の誤り", name, err)
		}
		if err != nil && strings.Contains(err.Error(), "段 last ") {
			t.Errorf("%s: 正しい段 last も誤りになりました: %v", name, err)
		}
	}

	// 応答の時間を測る筋書きの最後の段は、測る要求を送る、版に送る段でなければならない
	perfLast := "  - name: send\n    request: {method: GET, path: /x}\n  - name: tail\n    redis: {del: [k]}\n"
	if _, err := LoadScenario(writeScenario(t, kindsScenario("perf", perfLast))); err == nil || !strings.Contains(err.Error(), "最後の段 tail は、版に送る段") {
		t.Errorf("perf の最後の段が Redis を書き換える段の誤り = %v", err)
	}
}

func TestScenario_PrepareEachRejectsMeasureMemory(t *testing.T) {
	steps := "  - name: login\n    request: {method: POST, path: /api/auth/login}\n" +
		"  - name: verify\n    request: {method: POST, path: /api/auth/2fa/verify}\n    expect: {status: 200}\n"
	s, err := LoadScenario(writeScenario(t, "prepare_each: true\n"+kindsScenario("perf", steps)))
	if err != nil || !s.PrepareEach {
		t.Fatalf("prepare_each の筋書き = %+v, %v", s.PrepareEach, err)
	}
	if s, err := LoadScenario(writeScenario(t, kindsScenario("perf", steps))); err != nil || s.PrepareEach {
		t.Errorf("prepare_each の無い筋書き = %v, %v, want 偽", s.PrepareEach, err)
	}
	_, err = LoadScenario(writeScenario(t, "prepare_each: true\nmeasure_memory: true\n"+kindsScenario("perf", steps)))
	if err == nil || !strings.Contains(err.Error(), "prepare_each") || !strings.Contains(err.Error(), "measure_memory") {
		t.Errorf("prepare_each と measure_memory の誤り = %v", err)
	}
	if _, err := LoadScenario(writeScenario(t, "measure_memory: true\n"+kindsScenario("perf", steps))); err != nil {
		t.Errorf("measure_memory だけの筋書き: %v", err)
	}
	_, err = LoadScenario(writeScenario(t, "prepare_each: true\n"+kindsScenario("compare", steps)))
	if err == nil || !strings.Contains(err.Error(), "prepare_each") {
		t.Errorf("perf でない筋書きの prepare_each の誤り = %v", err)
	}
}

func TestLoadScenario_ReadsOIDCUsers(t *testing.T) {
	users := `oidc_users:
  google: {sub: g-1, name: 太郎, email: taro@example.com, email_verified: true}
  github:
    id: 42
    login: taro
    emails:
      - {email: taro@example.com, primary: true, verified: true}
`
	steps := "  - name: send\n    request: {method: GET, path: /x}\n"
	s, err := LoadScenario(writeScenario(t, users+kindsScenario("compare", steps)))
	if err != nil {
		t.Fatalf("oidc_users の筋書き: %v", err)
	}
	if s.OIDCUsers == nil || s.OIDCUsers.Google == nil || s.OIDCUsers.GitHub == nil {
		t.Fatalf("oidc_users = %+v", s.OIDCUsers)
	}
	wantGoogle := fakeoidc.GoogleUser{Sub: "g-1", Name: "太郎", Email: "taro@example.com", EmailVerified: true}
	wantGitHub := fakeoidc.GitHubUser{ID: 42, Login: "taro", Emails: []fakeoidc.GitHubEmail{{Email: "taro@example.com", Primary: true, Verified: true}}}
	// harness は、利用者を偽のログインのサービスの口へ JSON で送るので、JSON にして偽のログインのサービスの型で読めることを確かめる
	roundTrip := func(from, to any) {
		t.Helper()
		b, err := json.Marshal(from)
		if err != nil {
			t.Fatal(err)
		}
		dec := json.NewDecoder(strings.NewReader(string(b)))
		dec.DisallowUnknownFields()
		if err := dec.Decode(to); err != nil {
			t.Fatalf("%s: %v", b, err)
		}
	}
	var google fakeoidc.GoogleUser
	var github fakeoidc.GitHubUser
	roundTrip(s.OIDCUsers.Google, &google)
	roundTrip(s.OIDCUsers.GitHub, &github)
	if google != wantGoogle || !reflect.DeepEqual(github, wantGitHub) {
		t.Errorf("oidc_users = %+v %+v, want %+v %+v", google, github, wantGoogle, wantGitHub)
	}
	if s, err := LoadScenario(writeScenario(t, kindsScenario("compare", steps))); err != nil || s.OIDCUsers != nil {
		t.Errorf("oidc_users の無い筋書き = %+v, %v", s.OIDCUsers, err)
	}
	if _, err := LoadScenario(writeScenario(t, "oidc_users: {google: {subject: x}}\n"+kindsScenario("compare", steps))); err == nil {
		t.Error("oidc_users の知らない欄を受け付けました")
	}
}

func TestValidateCross_OnlyVersionSteps(t *testing.T) {
	// 版に送る段だけに expect の status を求め、ほかの3種類の段をはさんでもよい
	if _, err := LoadScenario(writeScenario(t, kindsScenario("cross", fourKindSteps))); err != nil {
		t.Errorf("4種類の段の cross の筋書き: %v", err)
	}
	for name, tc := range map[string]struct {
		steps string
		want  []string
	}{
		"最後の段が値を期限切れにする段": {
			"  - name: a\n    request: {method: GET, path: /x}\n    expect: {status: 200}\n" +
				"  - name: b\n    request: {method: GET, path: /y}\n    expect: {status: 200}\n" +
				"  - name: tail\n    expire: {var: link}\n",
			[]string{"最後の段", "tail"},
		},
		"最後の段が絶対の URL の段": {
			"  - name: a\n    request: {method: GET, path: /x}\n    expect: {status: 200}\n" +
				"  - name: b\n    request: {method: GET, path: /y}\n    expect: {status: 200}\n" +
				"  - name: tail\n    request: {method: GET, url: \"http://fakeoidc:8080/x\"}\n    expect: {status: 302}\n",
			[]string{"最後の段", "tail"},
		},
		"版に送る段の status が無い": {
			"  - name: a\n    request: {method: GET, path: /x}\n" +
				"  - name: b\n    request: {method: GET, path: /y}\n    expect: {status: 200}\n",
			[]string{"段 a ", "status"},
		},
		"版に送る段が1つ": {
			"  - name: a\n    request: {method: GET, url: \"http://fakeoidc:8080/x\"}\n" +
				"  - name: r\n    redis: {del: [k]}\n" +
				"  - name: b\n    request: {method: GET, path: /y}\n    expect: {status: 200}\n",
			[]string{"2つ以上", "1 段"},
		},
	} {
		_, err := LoadScenario(writeScenario(t, kindsScenario("cross", tc.steps)))
		if err == nil {
			t.Errorf("%s: 誤った筋書きを受け付けました", name)
			continue
		}
		for _, w := range tc.want {
			if !strings.Contains(err.Error(), w) {
				t.Errorf("%s: 誤り = %v, want %q を含む", name, err, w)
			}
		}
	}
}

func TestRedisStep_DelAndSetWithVersionValues(t *testing.T) {
	ctx := t.Context()
	container, err := testcontainers.Run(ctx, valkeyImage,
		testcontainers.WithExposedPorts("6379/tcp"),
		testcontainers.WithWaitStrategy(wait.ForListeningPort("6379/tcp")),
	)
	t.Cleanup(func() {
		if err := testcontainers.TerminateContainer(container); err != nil {
			t.Errorf("Valkey のコンテナを止められません: %v", err)
		}
	})
	if err != nil {
		t.Fatalf("Valkey のコンテナを動かせません: %v", err)
	}
	addr, err := container.PortEndpoint(ctx, "6379/tcp", "")
	if err != nil {
		t.Fatalf("つなぎ先を読めません: %v", err)
	}
	// Java 版と Go 版の Redis の代わりに、1つの Valkey の2つのデータベースを使う
	clients := map[string]*redis.Client{}
	for version, db := range map[string]int{"java": 0, "go": 1} {
		c := redis.NewClient(&redis.Options{Addr: addr, DB: db})
		t.Cleanup(func() { _ = c.Close() })
		clients[version] = c
	}
	values := map[string]string{"java": "j-1", "go": "g-1"}
	for version, c := range clients {
		v := values[version]
		if err := c.Set(ctx, "refresh:"+v, "old", 0).Err(); err != nil {
			t.Fatal(err)
		}
		if err := c.Set(ctx, "pwreset:"+v, "old", 0).Err(); err != nil {
			t.Fatal(err)
		}
		if err := c.Set(ctx, "keep", "k", 0).Err(); err != nil {
			t.Fatal(err)
		}
	}
	step := Step{Name: "expire-link", Redis: &RedisStep{
		Del: []string{"refresh:{token}", "pwreset:{token}"},
		Set: []RedisSet{{Key: "reset:{token}", Value: `{"userId":"{token}","n":1}`, TTLSeconds: 60}},
	}}
	sessions := map[string]*Session{}
	for version, v := range values {
		s := NewSession()
		s.vars["token"] = v
		sessions[version] = s
		if err := s.ApplyRedis(ctx, clients[version], step); err != nil {
			t.Fatalf("%s: ApplyRedis: %v", version, err)
		}
	}
	for version, c := range clients {
		v := values[version]
		keys, err := c.Keys(ctx, "*").Result()
		if err != nil {
			t.Fatal(err)
		}
		slices.Sort(keys)
		if want := []string{"keep", "reset:" + v}; !slices.Equal(keys, want) {
			t.Errorf("%s のキー = %v, want %v", version, keys, want)
		}
		if got, _ := c.Get(ctx, "reset:"+v).Result(); got != `{"userId":"`+v+`","n":1}` {
			t.Errorf("%s の値 = %q", version, got)
		}
		if ttl, _ := c.TTL(ctx, "reset:"+v).Result(); ttl <= 50*time.Second || ttl > 60*time.Second {
			t.Errorf("%s の有効な時間 = %s, want 60秒", version, ttl)
		}
	}

	// 差し込めない名前があるときと、差し込んだ値が JSON でないときは、Redis を書き換えずに段の名前を誤りに書く
	for name, bad := range map[string]*RedisStep{
		"nothing": {Del: []string{"keep"}, Set: []RedisSet{{Key: "x:{nothing}", Value: `1`, TTLSeconds: 1}}},
		"del":     {Del: []string{"keep", "y:{nothing}"}},
		"value":   {Del: []string{"keep"}, Set: []RedisSet{{Key: "x", Value: `{"a":{nothing}}`, TTLSeconds: 1}}},
		"JSON":    {Del: []string{"keep"}, Set: []RedisSet{{Key: "x", Value: `{"a":{token}}`, TTLSeconds: 1}}},
	} {
		err := sessions["java"].ApplyRedis(ctx, clients["java"], Step{Name: "bad", Redis: bad})
		if err == nil || !strings.Contains(err.Error(), "段 bad") || !strings.Contains(err.Error(), name) {
			t.Errorf("%s: 誤り = %v, want 段 bad と %q を含む", name, err, name)
		}
	}
	if n, _ := clients["java"].Exists(ctx, "keep").Result(); n != 1 {
		t.Errorf("誤りの段で keep を消しました")
	}
	// つなげない Redis は誤りにする
	closed := redis.NewClient(&redis.Options{Addr: "127.0.0.1:1", MaxRetries: -1, DialTimeout: time.Second})
	t.Cleanup(func() { _ = closed.Close() })
	if err := sessions["java"].ApplyRedis(ctx, closed, step); err == nil || !strings.Contains(err.Error(), "段 expire-link") {
		t.Errorf("つなげない Redis の誤り = %v", err)
	}
}
