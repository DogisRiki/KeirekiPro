//go:build compat

// Package compat は、Java 版と Go 版の backend を比べる検査の入口である。
// 版をまたぐ確認は TestCross で始まる名前で、make compat-cross が動かす。
package compat

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/jackc/pgx/v5"

	"github.com/DogisRiki/KeirekiPro/backend/compat/harness"
)

// writeScenario は、筋書きを一時のファイルに書いて読み込む。
func writeScenario(t *testing.T, content string) harness.Scenario {
	t.Helper()
	file := filepath.Join(t.TempDir(), "scenario.yaml")
	if err := os.WriteFile(file, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	s, err := harness.LoadScenario(file)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

// hit は、偽の版が受けた1つの要求である。
type hit struct {
	Version, Method, Path, Cookie, CSRF string
}

// fakeVersions は、Java 版と Go 版の位置に置く、受けた要求を記録する偽の版である。
// どちらの版も、同じ Cookie を受け付け、作った資料の ID を返す。fail を返す版の段は、500 を返す。
type fakeVersions struct {
	mu   sync.Mutex
	hits []hit
	urls map[string]string
}

func newFakeVersions(t *testing.T, fail func(version, path string) bool) *fakeVersions {
	t.Helper()
	f := &fakeVersions{urls: map[string]string{}}
	for _, version := range []string{harness.VersionJava, harness.VersionGo} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			f.mu.Lock()
			f.hits = append(f.hits, hit{version, r.Method, r.URL.Path, r.Header.Get("Cookie"), r.Header.Get("X-XSRF-TOKEN")})
			f.mu.Unlock()
			if fail != nil && fail(version, r.URL.Path) {
				w.WriteHeader(http.StatusInternalServerError)
				_, _ = w.Write([]byte(`{"message":"壊れました"}`))
				return
			}
			switch r.URL.Path {
			case "/api/auth/login":
				http.SetCookie(w, &http.Cookie{Name: "accessToken", Value: "a-1", Path: "/", Secure: true, HttpOnly: true, SameSite: http.SameSiteLaxMode})
				http.SetCookie(w, &http.Cookie{Name: "XSRF-TOKEN", Value: "x-1", Path: "/", Secure: true, HttpOnly: true, SameSite: http.SameSiteLaxMode})
				_, _ = w.Write([]byte(`{"id":"u-1"}`))
			case "/api/resumes":
				w.WriteHeader(http.StatusCreated)
				_, _ = w.Write([]byte(`{"id":"r-1"}`))
			default:
				_, _ = w.Write([]byte(`{"name":"保存した名前"}`))
			}
		}))
		t.Cleanup(srv.Close)
		f.urls[version] = srv.URL
	}
	return f
}

func (f *fakeVersions) take() []hit {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := f.hits
	f.hits = nil
	return out
}

// fourSteps は、ログインし、もう一方の版で作り、同じ版で直し、最後に保存した内容を読む筋書きである。
const fourSteps = `name: login-create-update-read
group: 1
modes: [cross]
steps:
  - name: login
    request: {method: POST, path: /api/auth/login, json: {email: user1@example.com}}
    expect: {status: 200, fields: [$.id]}
  - name: create
    to: other
    request: {method: POST, path: /api/resumes, csrf: true, json: {name: 経歴書}}
    capture: {resume: $.id}
    expect: {status: 201}
  - name: update
    to: same
    request: {method: PUT, path: '/api/resumes/{resume}/basic', csrf: true, json: {name: 保存した名前}}
    expect: {status: 200}
  - name: read
    request: {method: GET, path: '/api/resumes/{resume}'}
    expect: {status: 200, fields: [$.name]}
`

func TestCross_ThreeDirectionsRun(t *testing.T) {
	s := writeScenario(t, fourSteps)
	fake := newFakeVersions(t, nil)
	j, g := harness.VersionJava, harness.VersionGo
	want := map[string][]string{
		harness.CrossJavaToGo:  {j, g, g, j},
		harness.CrossGoToJava:  {g, j, j, g},
		harness.CrossAlternate: {j, g, j, g},
	}
	if !slices.Equal(harness.CrossDirections, []string{harness.CrossJavaToGo, harness.CrossGoToJava, harness.CrossAlternate}) {
		t.Fatalf("送り先の組 = %v, want 3つ", harness.CrossDirections)
	}
	for _, direction := range harness.CrossDirections {
		if f := harness.RunCross(t.Context(), http.DefaultClient, s, direction, fake.urls); f != nil {
			t.Fatalf("%s: 失敗しました: %+v", direction, f)
		}
		hits := fake.take()
		var versions []string
		for _, h := range hits {
			versions = append(versions, h.Version)
		}
		if !slices.Equal(versions, want[direction]) {
			t.Errorf("%s: 送った版 = %v, want %v", direction, versions, want[direction])
		}
		if len(hits) != 4 {
			continue
		}
		// 1つ目の版が渡した Cookie を、2つ目からの版にも送る
		for _, h := range hits[1:] {
			if !strings.Contains(h.Cookie, "accessToken=a-1") || !strings.Contains(h.Cookie, "XSRF-TOKEN=x-1") {
				t.Errorf("%s: %s %s の Cookie = %q, want 1つ目の版の Cookie", direction, h.Version, h.Path, h.Cookie)
			}
		}
		if hits[1].CSRF != "x-1" || hits[2].CSRF != "x-1" || hits[3].CSRF != "" {
			t.Errorf("%s: 偽の送信の検査のヘッダ = %q %q %q, want x-1 x-1 空", direction, hits[1].CSRF, hits[2].CSRF, hits[3].CSRF)
		}
		// 2つ目の段で取り出した ID を、3つ目と4つ目の段のパスに差し込む
		if hits[2].Path != "/api/resumes/r-1/basic" || hits[3].Path != "/api/resumes/r-1" || hits[3].Method != http.MethodGet {
			t.Errorf("%s: パス = %s %s %s", direction, hits[2].Path, hits[3].Method, hits[3].Path)
		}
	}
}

func TestCross_WrongStatusFailsWithStepAndDirection(t *testing.T) {
	s := writeScenario(t, fourSteps)
	// Go 版の位置の、経歴書を直す口だけが 500 を返す
	fake := newFakeVersions(t, func(version, path string) bool {
		return version == harness.VersionGo && strings.HasSuffix(path, "/basic")
	})
	report := harness.CrossReport{Scenario: s.Name, Directions: harness.CrossDirections}
	sent := map[string]int{}
	for _, direction := range harness.CrossDirections {
		if f := harness.RunCross(t.Context(), http.DefaultClient, s, direction, fake.urls); f != nil {
			report.Failures = append(report.Failures, *f)
		}
		sent[direction] = len(fake.take())
	}
	if !report.Failed() || len(report.Failures) != 1 {
		t.Fatalf("失敗 = %+v, want Java から Go への組の1件", report.Failures)
	}
	f := report.Failures[0]
	if f.Direction != harness.CrossJavaToGo || f.Step.Index != 3 || f.Step.Name != "update" || f.Version != harness.VersionGo {
		t.Errorf("失敗 = %+v, want java-to-go の3つ目の段 update を go に送った失敗", f)
	}
	// 失敗した段で止め、最後の段は送らない
	if sent[harness.CrossJavaToGo] != 3 || sent[harness.CrossGoToJava] != 4 || sent[harness.CrossAlternate] != 4 {
		t.Errorf("送った要求の数 = %v, want java-to-go 3、ほかは 4", sent)
	}
	text := report.String()
	for _, w := range []string{"login-create-update-read", "送り先の組: java-to-go", "段: 3「update」", "送った版: go", "ステータスが 500 でした。期待は 200 です", "壊れました"} {
		if !strings.Contains(text, w) {
			t.Errorf("報告に %q がありません:\n%s", w, text)
		}
	}
}

// selfPair は、Go 版のイメージを両方の位置に置いて確かめる筋書きである。偽の送信の検査の Cookie を1つ目の位置で受け取り、
// もう一方の位置で使う。Go 版の経歴書の操作はまだ 501 を返すので、偽の送信の検査を通ったことを 501 で確かめる。
const selfPair = `name: self-pair
group: 0
fixtures: [users/basic.sql, resumes/many-pages.sql]
modes: [cross]
steps:
  - name: get-token
    request: {method: GET, path: /healthz}
    expect: {status: 200, fields: [$.status]}
  - name: delete-with-token
    to: other
    request: {method: DELETE, path: /api/resumes/00000000-0000-4000-8000-000000000201, csrf: true}
    expect: {status: 501}
  - name: read
    request: {method: GET, path: /healthz}
    expect: {status: 200}
`

func TestCross_SelfPairPasses(t *testing.T) {
	ctx := t.Context()
	images := buildImages(t, harness.ImageGo, harness.ImagePostgres, harness.ImageRedis, harness.ImageFakeAWS, harness.ImageFakeOIDC)
	env, err := harness.NewEnv(ctx)
	if err != nil {
		t.Fatal(err)
	}
	env.Cleanup(t)
	cross, err := harness.StartCrossEnv(ctx, env, images, map[string]harness.Backend{
		harness.VersionJava: harness.GoBackend(images[harness.ImageGo]),
		harness.VersionGo:   harness.GoBackend(images[harness.ImageGo]),
	})
	if cross != nil {
		t.Cleanup(func() { _ = cross.Close() })
	}
	if err != nil {
		t.Fatal(err)
	}
	if cross.URLs[harness.VersionJava] == cross.URLs[harness.VersionGo] {
		t.Fatalf("2つの位置が同じコンテナです: %v", cross.URLs)
	}

	report, err := cross.Run(ctx, writeScenario(t, selfPair))
	if err != nil {
		t.Fatal(err)
	}
	if report.Failed() {
		writeReport(t, report)
		t.Fatalf("同じイメージの組が失敗しました:\n%s", report)
	}

	// 筋書きの初めのデータが入っていることと、Reset が、履歴の入れた行を残してほかを空にすることを確かめる
	if n := count(t, cross.DBConn, "users"); n != 2 {
		t.Errorf("筋書きのあとの利用者 = %d 人, want 2 人", n)
	}
	if err := cross.Redis.Set(ctx, "compat:left", "1", 0).Err(); err != nil {
		t.Fatal(err)
	}
	if err := cross.Reset(ctx); err != nil {
		t.Fatal(err)
	}
	for table, want := range map[string]bool{"users": false, "resumes": false, "roles": true} {
		if n := count(t, cross.DBConn, table); (n > 0) != want {
			t.Errorf("Reset のあとの %s の行 = %d, want 行がある = %v", table, n, want)
		}
	}
	if n, err := cross.Redis.DBSize(ctx).Result(); err != nil || n != 0 {
		t.Errorf("Reset のあとの Redis のキー = %d, %v, want 0", n, err)
	}
}

// TestCross_Scenarios は、backend/compat/scenarios/ の、版をまたぐ動かし方の筋書きを、Java 版と Go 版で動かす。
// 筋書きは、まとまりの spec で足す。筋書きが1つも無いうちは、イメージを組み立てずに、その旨を記録して終える。
func TestCross_Scenarios(t *testing.T) {
	scenarios, err := harness.LoadScenarios(harness.ScenariosDir(), harness.ModeCross)
	if err != nil {
		t.Fatal(err)
	}
	if len(scenarios) == 0 {
		t.Logf("%s に、版をまたぐ動かし方の筋書きがまだありません", harness.ScenariosDir())
		return
	}
	ctx := t.Context()
	images := buildImages(t, harness.ImageJava, harness.ImageGo, harness.ImagePostgres, harness.ImageRedis, harness.ImageFakeAWS, harness.ImageFakeOIDC)
	env, err := harness.NewEnv(ctx)
	if err != nil {
		t.Fatal(err)
	}
	env.Cleanup(t)
	cross, err := harness.StartCrossEnv(ctx, env, images, map[string]harness.Backend{
		harness.VersionJava: harness.JavaBackend(images[harness.ImageJava]),
		harness.VersionGo:   harness.GoBackend(images[harness.ImageGo]),
	})
	if cross != nil {
		t.Cleanup(func() { _ = cross.Close() })
	}
	if err != nil {
		t.Fatal(err)
	}
	for _, s := range scenarios {
		t.Run(s.Name, func(t *testing.T) {
			report, err := cross.Run(ctx, s)
			if err != nil {
				t.Fatal(err)
			}
			if report.Failed() {
				writeReport(t, report)
				t.Errorf("版をまたぐ確認が失敗しました:\n%s", report)
			}
		})
	}
}

// buildImages は、イメージを組み立て、テストの終わりに消すように登録する。
func buildImages(t *testing.T, names ...string) harness.Images {
	t.Helper()
	root, err := harness.RepoRoot()
	if err != nil {
		t.Fatal(err)
	}
	var buildLog bytes.Buffer
	images, err := harness.BuildImages(t.Context(), root, &buildLog, names...)
	t.Cleanup(func() {
		if err := images.Remove(context.Background()); err != nil {
			t.Errorf("組み立てたイメージを消せません: %v", err)
		}
	})
	if err != nil {
		t.Fatalf("BuildImages: %v\n%s", err, buildLog.String())
	}
	return images
}

// writeReport は、版をまたぐ確認の報告を ReportDir に書く。CI はこのフォルダを成果物に残す。
func writeReport(t *testing.T, report harness.CrossReport) {
	t.Helper()
	file, err := report.Write(harness.ReportDir())
	if err != nil {
		t.Errorf("報告を書けません: %v", err)
		return
	}
	t.Logf("報告を %s に書きました", file)
}

func count(t *testing.T, connString, table string) int {
	t.Helper()
	conn, err := pgx.Connect(t.Context(), connString)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = conn.Close(context.Background()) }()
	var n int
	if err := conn.QueryRow(t.Context(), "SELECT count(*) FROM "+pgx.Identifier{table}.Sanitize()).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}
