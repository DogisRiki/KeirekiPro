//go:build compat

package compat

import (
	"sync"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/compat/harness"
)

// 応答の時間の比べ方は TestPerf で始まる名前で、make compat-perf が動かす。PR の検査では動かさない。

// selfPerf は、Go 版のイメージを両方の位置に置いて、応答の時間の比べ方を確かめる筋書きである。
// 1つ目の段でログインし、2つ目の段で偽の送信の検査の Cookie を受け取り、最後の段を測る。
// Go 版の経歴書の復元は、ファイルの版の無い本文に 400 で答えるので、ログインの確かめと偽の送信の検査を通ったことを
// 400 で確かめる。
const selfPerf = `name: self-perf
group: 0
fixtures: [users/basic.sql]
modes: [perf]
measure_memory: true
steps:
  - name: login
    request: {method: POST, path: /api/auth/login, json: {email: user1@example.com, password: Passw0rd!}}
    expect: {status: 200}
  - name: get-token
    request: {method: GET, path: /healthz}
    expect: {status: 200}
  - name: restore-with-token
    request: {method: POST, path: /api/resumes/restore, json: {}, csrf: true}
    expect: {status: 400}
`

func TestPerf_SelfPairRuns(t *testing.T) {
	images := buildImages(t, harness.ImageGo, harness.ImagePostgres, harness.ImageRedis, harness.ImageFakeAWS, harness.ImageFakeOIDC)
	envs := startPerfEnvs(t, images, map[string]harness.Backend{
		harness.VersionJava: harness.GoBackend(images[harness.ImageGo]),
		harness.VersionGo:   harness.GoBackend(images[harness.ImageGo]),
	})
	if envs[harness.VersionJava].DBConn == envs[harness.VersionGo].DBConn {
		t.Fatalf("2つの版が同じデータベースにつながっています: %s", envs[harness.VersionGo].DBConn)
	}
	// 両方の位置に置いた Go 版の本番のイメージは、起動の時間を測られている
	for _, version := range []string{harness.VersionJava, harness.VersionGo} {
		if d := envs[version].Startup; d <= 0 || d > harness.GoStartupLimit {
			t.Errorf("版 %s の位置の Go 版の起動の時間 = %s, want 0 より長く %s 以内", version, d, harness.GoStartupLimit)
		}
	}

	opts := harness.PerfOptions{Warmup: 2, Samples: 10, Concurrency: harness.PerfConcurrency}
	report, err := harness.RunPerf(t.Context(), envs, []harness.Scenario{writeScenario(t, selfPerf)}, opts)
	if err != nil {
		t.Fatal(err)
	}
	writePerfReport(t, report)
	if len(report.Latencies) != 1 || report.Latencies[0].Operation != "self-perf" ||
		report.Latencies[0].Java <= 0 || report.Latencies[0].Go <= 0 {
		t.Errorf("応答の時間 = %+v, want self-perf の両方の版の時間", report.Latencies)
	}
	if len(report.Memories) != 1 || report.Memories[0].PeakBytes == 0 {
		t.Errorf("メモリの最大 = %+v, want self-perf の Go 版のメモリの最大", report.Memories)
	}
	if report.Failed() {
		t.Errorf("同じイメージの組が上限を超えました:\n%s", report)
	}
	// 筋書きの初めのデータが、それぞれの版のデータベースに入っている
	for version, env := range envs {
		if n := count(t, env.DBConn, "users"); n != 2 {
			t.Errorf("版 %s の利用者 = %d 人, want 2 人", version, n)
		}
	}
}

// scenariosPerf は、backend/compat/scenarios/ の、応答の時間の比べ方の筋書きを、Java 版と Go 版で測った結果である。
// TestPerf_AllOperationsWithinTolerance と TestPerf_PDFMemoryWithin1792MB は、同じ測った結果を確かめる。
// 測るのに時間がかかるので、先に動いたテストが1回だけ測り、あとのテストは測った結果を使う。
var scenariosPerf struct {
	once     sync.Once
	report   harness.PerfReport
	measured bool
}

// measureScenarios は、応答の時間の比べ方の筋書きを測った結果を返す。まだ測っていなければ、ここで測る。
// 測るのに失敗したときは、測ったテストがその理由で失敗し、あとのテストも失敗にする。
func measureScenarios(t *testing.T) harness.PerfReport {
	t.Helper()
	scenariosPerf.once.Do(func() {
		scenariosPerf.report = runScenariosPerf(t)
		scenariosPerf.measured = true
	})
	if !scenariosPerf.measured {
		t.Fatal("応答の時間の比べ方の筋書きを測れませんでした。先に測ったテストの記録に理由があります")
	}
	return scenariosPerf.report
}

// runScenariosPerf は、応答の時間の比べ方の筋書きを、Java 版と Go 版で測り、報告を ReportDir に書く。
// 筋書きが1つも無いときは、50の操作を求める TestCoverage_Operations が失敗するので、ここでも失敗にする。
func runScenariosPerf(t *testing.T) harness.PerfReport {
	t.Helper()
	scenarios, err := harness.LoadScenarios(harness.ScenariosDir(), harness.ModePerf)
	if err != nil {
		t.Fatal(err)
	}
	if len(scenarios) == 0 {
		t.Fatalf("%s に、応答の時間の比べ方の筋書きがありません", harness.ScenariosDir())
	}
	images := buildImages(t, harness.ImageJava, harness.ImageGo, harness.ImagePostgres, harness.ImageRedis, harness.ImageFakeAWS, harness.ImageFakeOIDC)
	envs := startPerfEnvs(t, images, map[string]harness.Backend{
		harness.VersionJava: harness.JavaBackend(images[harness.ImageJava]),
		harness.VersionGo:   harness.GoBackend(images[harness.ImageGo]),
	})
	t.Logf("Go 版の起動から /healthz が 200 を返すまでの時間: %s", envs[harness.VersionGo].Startup)
	report, err := harness.RunPerf(t.Context(), envs, scenarios, harness.DefaultPerfOptions)
	if err != nil {
		t.Fatal(err)
	}
	writePerfReport(t, report)
	t.Logf("応答の時間の比べ方の結果:\n%s", report)
	return report
}

// 要件9の受入基準7: 筋書きで測ったすべての操作で、Go 版の95パーセンタイルが、Java 版の95パーセンタイルの1.2倍に20ミリ秒を
// 足した時間を超えない。
func TestPerf_AllOperationsWithinTolerance(t *testing.T) {
	report := measureScenarios(t)
	if len(report.Latencies) == 0 {
		t.Fatal("応答の時間を測った操作がありません")
	}
	for _, l := range report.Latencies {
		if !l.Within() {
			t.Errorf("操作 %s: Go 版の95パーセンタイル %s が、上限 %s を超えました。Java 版の95パーセンタイルは %s",
				l.Operation, l.Go, l.Limit(), l.Java)
		}
	}
}

// 要件9の受入基準7: PDF の出力を同時に2件送ったときの Go 版のコンテナのメモリの最大が、タスク定義の
// memoryReservation 1792MB を超えない。
func TestPerf_PDFMemoryWithin1792MB(t *testing.T) {
	report := measureScenarios(t)
	if len(report.Memories) == 0 {
		t.Fatal("メモリの最大を測った操作がありません。PDF の出力の筋書きに measure_memory: true を書きます")
	}
	for _, m := range report.Memories {
		if !m.Within() {
			t.Errorf("操作 %s: 同時に %d 件送ったときの Go 版のコンテナのメモリの最大 %d バイトが、上限 %d バイトを超えました",
				m.Operation, harness.PerfConcurrency, m.PeakBytes, harness.MemoryLimitBytes)
		}
	}
}

// startPerfEnvs は、版ごとに別の Docker のネットワークを作り、その版だけの環境を起動する。
func startPerfEnvs(t *testing.T, images harness.Images, backends map[string]harness.Backend) map[string]*harness.PerfEnv {
	t.Helper()
	envs := map[string]*harness.PerfEnv{}
	for _, version := range []string{harness.VersionJava, harness.VersionGo} {
		env, err := harness.NewEnv(t.Context())
		if err != nil {
			t.Fatal(err)
		}
		env.Cleanup(t)
		p, err := harness.StartPerfEnv(t.Context(), env, images, version, backends[version])
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = p.Close() })
		envs[version] = p
	}
	return envs
}

// writePerfReport は、応答の時間の比べ方の報告を ReportDir に書く。
func writePerfReport(t *testing.T, report harness.PerfReport) {
	t.Helper()
	file, err := report.Write(harness.ReportDir())
	if err != nil {
		t.Errorf("報告を書けません: %v", err)
		return
	}
	t.Logf("報告を %s に書きました", file)
}
