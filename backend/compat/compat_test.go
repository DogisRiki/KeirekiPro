//go:build compat

package compat

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"strconv"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/compat/harness"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/migrate"
)

// make compat は、TestCross_ と TestPerf_ で始まる名前を除く、このパッケージのテストを動かす。
// 版をまたぐ確認は make compat-cross が、応答の時間の比べ方は make compat-perf が動かす。

// requireAllOperations は、TestCoverage_Operations が、仕様書のすべての操作を筋書きに求めるかである。
// false の間は、progress.md で完了と記したまとまりの操作だけを、そのまとまりの筋書きに求める。
// 段階4の切り替えの準備で true にする。
const requireAllOperations = false

// TestCompare_Scenarios は、backend/compat/scenarios/ の、比べる動かし方の筋書きを、Java 版と Go 版で動かして比べる。
// 筋書きは、まとまりの spec で足す。筋書きが1つも無いうちは、イメージを組み立てずに、その旨を記録して終える。
func TestCompare_Scenarios(t *testing.T) {
	scenarios, err := harness.LoadScenarios(harness.ScenariosDir(), harness.ModeCompare)
	if err != nil {
		t.Fatal(err)
	}
	if len(scenarios) == 0 {
		t.Logf("%s に、比べる動かし方の筋書きがまだありません", harness.ScenariosDir())
		return
	}
	images := buildImages(t, harness.ImageJava, harness.ImageGo, harness.ImagePostgres, harness.ImageRedis, harness.ImageFakeAWS, harness.ImageFakeOIDC)
	cmp := startCompareEnv(t, images, map[string]harness.Backend{
		harness.VersionJava: harness.JavaBackend(images[harness.ImageJava]),
		harness.VersionGo:   harness.GoBackend(images[harness.ImageGo]),
	})
	for _, s := range scenarios {
		t.Run(s.Name, func(t *testing.T) {
			report, err := cmp.Run(t.Context(), s)
			if err != nil {
				t.Fatal(err)
			}
			if report.Failed() {
				writeCompareReport(t, report)
				t.Errorf("比べる検査が違いを見つけました:\n%s", report)
			}
		})
	}
}

// TestCoverage_Operations は、筋書きに出てくる操作が足りているかを確かめる。requireAllOperations の値によらず、必ず動く。
func TestCoverage_Operations(t *testing.T) {
	ops, err := harness.LoadOperations(harness.OpenAPIFile())
	if err != nil {
		t.Fatal(err)
	}
	if len(ops) != 50 {
		t.Fatalf("仕様書の操作 = %d, want 50", len(ops))
	}
	progress, err := harness.ProgressFile()
	if err != nil {
		t.Fatal(err)
	}
	completed, err := harness.LoadCompletedGroups(progress)
	if err != nil {
		t.Fatal(err)
	}
	scenarios, err := harness.LoadScenarios(harness.ScenariosDir(), harness.ModeCompare)
	if err != nil {
		t.Fatal(err)
	}
	for _, op := range harness.MissingOperations(ops, scenarios, completed, requireAllOperations) {
		t.Errorf("操作 %s(%s %s、まとまり %d)が、比べる動かし方の筋書きに出てきません", op.ID, op.Method, op.Path, op.Group)
	}
	t.Logf("仕様書の操作 %d 個、完了と記したまとまり %v、比べる動かし方の筋書き %d 個、すべての操作を求める = %v",
		len(ops), completed, len(scenarios), requireAllOperations)
}

// selfCompare は、比べる検査そのものを確かめる筋書きである。偽の送信の検査の Cookie を1つ目の段で受け取り、
// 2つ目の段で使う。Go 版の経歴書の操作はまだ 501 を返すので、偽の送信の検査を通ったことを 501 で確かめる。
const selfCompare = `name: self-compare
group: 0
fixtures: [users/basic.sql, resumes/many-pages.sql]
modes: [compare]
steps:
  - name: get-token
    request: {method: GET, path: /healthz}
    expect: {status: 200, fields: [$.status]}
  - name: delete-with-token
    request: {method: DELETE, path: /api/resumes/00000000-0000-4000-8000-000000000201, csrf: true}
    expect: {status: 501}
`

// startSelfCompare は、Go 版のイメージを両方の位置に置いた比べる環境を起動する。
func startSelfCompare(t *testing.T) *harness.CompareEnv {
	t.Helper()
	images := buildImages(t, harness.ImageGo, harness.ImagePostgres, harness.ImageRedis, harness.ImageFakeAWS, harness.ImageFakeOIDC)
	return startCompareEnv(t, images, map[string]harness.Backend{
		harness.VersionJava: harness.GoBackend(images[harness.ImageGo]),
		harness.VersionGo:   harness.GoBackend(images[harness.ImageGo]),
	})
}

// 要件4の受入基準5: 同じイメージを両方の位置に置くと、違いは0件になる。
func TestSelf_SameImageNoDiff(t *testing.T) {
	cmp := startSelfCompare(t)
	if cmp.Stores[harness.VersionJava].DBConn == cmp.Stores[harness.VersionGo].DBConn {
		t.Fatalf("2つの版が同じデータベースにつながっています: %s", cmp.Stores[harness.VersionGo].DBConn)
	}
	// 両方の位置に置いた Go 版の本番のイメージは、起動の時間を測られ、上限の内に起動している
	for _, version := range []string{harness.VersionJava, harness.VersionGo} {
		if d, ok := cmp.Startup[version]; !ok || d <= 0 || d > harness.GoStartupLimit {
			t.Errorf("版 %s の位置の Go 版の起動の時間 = %s(測った: %t), want 0 より長く %s 以内", version, d, ok, harness.GoStartupLimit)
		}
	}
	report, err := cmp.Run(t.Context(), writeScenario(t, selfCompare))
	if err != nil {
		t.Fatal(err)
	}
	if report.Failed() || len(report.Allowed) != 0 {
		writeCompareReport(t, report)
		t.Fatalf("同じイメージの組で違いが見つかりました:\n%s", report)
	}
	// 筋書きの初めのデータが、それぞれの版のデータベースに入っている
	for version, st := range cmp.Stores {
		if n := count(t, st.DBConn, "users"); n != 2 {
			t.Errorf("版 %s の利用者 = %d 人, want 2 人", version, n)
		}
	}
}

// 要件4の受入基準6: Go 版の位置に、応答の本文を1文字変える偽物を置くと、検査は失敗し、違いの段と場所と両方の値を報告する。
func TestSelf_OneCharFakeFails(t *testing.T) {
	cmp := startSelfCompare(t)
	cmp.URLs[harness.VersionGo] = oneCharFake(t, cmp.URLs[harness.VersionGo])

	report, err := cmp.Run(t.Context(), writeScenario(t, selfCompare))
	if err != nil {
		t.Fatal(err)
	}
	if !report.Failed() || len(report.Diffs) != 1 {
		t.Fatalf("違い = %+v, want 1件", report.Diffs)
	}
	d := report.Diffs[0]
	if d.Target != harness.TargetBody || d.Path != "$.message" || d.Step.Index != 2 || d.Step.Name != "delete-with-token" || d.Step.Operation != "deleteResume" {
		t.Errorf("違い = %+v, want 2段目 delete-with-token(deleteResume)の本文の $.message", d)
	}
	text := report.String()
	for _, want := range []string{"未実装です。", "未実装です！", "deleteResume"} {
		if !strings.Contains(text, want) {
			t.Errorf("報告に %q がありません:\n%s", want, text)
		}
	}
}

// 要件4の受入基準7: 変えた動きの一覧の match に当たる違いだけなら、検査は通り、許した違いを報告に残す。
func TestSelf_MatchedDiffPasses(t *testing.T) {
	cmp := startSelfCompare(t)
	cmp.URLs[harness.VersionGo] = oneCharFake(t, cmp.URLs[harness.VersionGo])
	cmp.Behaviors = []harness.ChangedBehavior{{
		ID:      "CB-TEST",
		Matches: harness.Matches{{Operation: "deleteResume", Target: harness.TargetBody, Path: "$.message", Status: http.StatusNotImplemented}},
	}}

	report, err := cmp.Run(t.Context(), writeScenario(t, selfCompare))
	if err != nil {
		t.Fatal(err)
	}
	if report.Failed() {
		t.Fatalf("match に当たる違いだけなのに失敗しました:\n%s", report)
	}
	if len(report.Allowed) != 1 || report.Allowed[0].ID != "CB-TEST" || report.Allowed[0].Diff.Path != "$.message" {
		t.Errorf("許した違い = %+v, want CB-TEST の $.message の1件", report.Allowed)
	}
}

// oneCharFake は、target に送り、応答の本文の「です。」を「です！」に変えて返す偽物を起動し、その URL を返す。
func oneCharFake(t *testing.T, target string) string {
	t.Helper()
	u, err := url.Parse(target)
	if err != nil {
		t.Fatal(err)
	}
	proxy := &httputil.ReverseProxy{
		Rewrite: func(r *httputil.ProxyRequest) { r.SetURL(u) },
		ModifyResponse: func(resp *http.Response) error {
			body, err := io.ReadAll(resp.Body)
			if err != nil {
				return err
			}
			_ = resp.Body.Close()
			body = bytes.ReplaceAll(body, []byte("です。"), []byte("です！"))
			resp.Body = io.NopCloser(bytes.NewReader(body))
			resp.ContentLength = int64(len(body))
			resp.Header.Set("Content-Length", strconv.Itoa(len(body)))
			return nil
		},
	}
	srv := httptest.NewServer(proxy)
	t.Cleanup(srv.Close)
	return srv.URL
}

// 要件12の受入基準4: migrate の部品の Apply で作った表と履歴を、Java 版の Flyway は起動のときの validate で通し、
// 履歴に行を足さない。Java 版が起動したあとも、Go 版の確かめるだけの動かし方は、7つの版をすべて適用済みと読む。
func TestApply_JavaFlywayValidatePasses(t *testing.T) {
	ctx := t.Context()
	images := buildImages(t, harness.ImageJava, harness.ImagePostgres, harness.ImageRedis, harness.ImageFakeAWS, harness.ImageFakeOIDC)
	env, err := harness.NewEnv(ctx)
	if err != nil {
		t.Fatal(err)
	}
	env.Cleanup(t)
	// StartPerfEnv は、Apply で表を作ってから、Java 版を起動し、起動の確認が 200 を返すまで待つ。
	// Flyway の validate が通らなければ、Java 版は起動に失敗する。
	java, err := harness.StartPerfEnv(ctx, env, images, harness.VersionJava, harness.JavaBackend(images[harness.ImageJava]))
	if java != nil {
		t.Cleanup(func() { _ = java.Close() })
	}
	if err != nil {
		t.Fatalf("Apply で作った表に Java 版を起動できません: %v", err)
	}

	var rows, failed, baseline int
	err = func() error {
		conn, err := pgx.Connect(ctx, java.DBConn)
		if err != nil {
			return err
		}
		defer func() { _ = conn.Close(context.Background()) }()
		return conn.QueryRow(ctx, `SELECT count(*), count(*) FILTER (WHERE NOT success), count(*) FILTER (WHERE type = 'BASELINE')
			FROM flyway_schema_history`).Scan(&rows, &failed, &baseline)
	}()
	if err != nil {
		t.Fatal(err)
	}
	if rows != 7 || failed != 0 || baseline != 0 {
		t.Errorf("Java 版の起動のあとの履歴 = %d 行(失敗 %d 行、BASELINE %d 行), want 7 行、失敗 0 行、BASELINE 0 行", rows, failed, baseline)
	}

	pool, err := pgxpool.New(ctx, java.DBConn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	files, err := backend.Migrations()
	if err != nil {
		t.Fatal(err)
	}
	result, err := migrate.Run(ctx, pool, files, migrate.ValidateOnly)
	if err != nil || len(result.Validated) != 7 || len(result.Pending) != 0 {
		t.Errorf("migrate.Run(ValidateOnly) = %+v, %v, want 7 つが適用済みで、残りが0", result, err)
	}
}

// startCompareEnv は、1つの Docker のネットワークに比べる環境を起動する。
func startCompareEnv(t *testing.T, images harness.Images, backends map[string]harness.Backend) *harness.CompareEnv {
	t.Helper()
	env, err := harness.NewEnv(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	env.Cleanup(t)
	cmp, err := harness.StartCompareEnv(t.Context(), env, images, backends)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmp.Close() })
	return cmp
}

// writeCompareReport は、比べる検査の報告を ReportDir に書く。CI はこのフォルダを成果物に残す。
func writeCompareReport(t *testing.T, report harness.Report) {
	t.Helper()
	file, err := report.Write(harness.ReportDir())
	if err != nil {
		t.Errorf("報告を書けません: %v", err)
		return
	}
	t.Logf("報告を %s に書きました", file)
}
