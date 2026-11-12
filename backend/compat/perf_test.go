//go:build compat

package compat

import (
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/compat/harness"
)

// 応答の時間の比べ方は TestPerf で始まる名前で、make compat-perf が動かす。PR の検査では動かさない。

// selfPerf は、Go 版のイメージを両方の位置に置いて、応答の時間の比べ方を確かめる筋書きである。
// 1つ目の段でログインし、2つ目の段で偽の送信の検査の Cookie を受け取り、最後の段を測る。
// Go 版の経歴書の操作はまだ 501 を返すので、ログインの確かめと偽の送信の検査を通ったことを 501 で確かめる。
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
  - name: delete-with-token
    request: {method: DELETE, path: /api/resumes/00000000-0000-4000-8000-000000000201, csrf: true}
    expect: {status: 501}
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

// TestPerf_Scenarios は、backend/compat/scenarios/ の、応答の時間の比べ方の筋書きを、Java 版と Go 版で測って比べる。
// 筋書きは、まとまりの spec で足す。筋書きが1つも無いうちは、イメージを組み立てずに、その旨を記録して終える。
func TestPerf_Scenarios(t *testing.T) {
	scenarios, err := harness.LoadScenarios(harness.ScenariosDir(), harness.ModePerf)
	if err != nil {
		t.Fatal(err)
	}
	if len(scenarios) == 0 {
		t.Logf("%s に、応答の時間の比べ方の筋書きがまだありません", harness.ScenariosDir())
		return
	}
	images := buildImages(t, harness.ImageJava, harness.ImageGo, harness.ImagePostgres, harness.ImageRedis, harness.ImageFakeAWS, harness.ImageFakeOIDC)
	envs := startPerfEnvs(t, images, map[string]harness.Backend{
		harness.VersionJava: harness.JavaBackend(images[harness.ImageJava]),
		harness.VersionGo:   harness.GoBackend(images[harness.ImageGo]),
	})
	report, err := harness.RunPerf(t.Context(), envs, scenarios, harness.DefaultPerfOptions)
	if err != nil {
		t.Fatal(err)
	}
	writePerfReport(t, report)
	t.Logf("応答の時間の比べ方の結果:\n%s", report)
	if report.Failed() {
		t.Errorf("上限を超えた操作があります:\n%s", report)
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
