//go:build compat

package harness

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	tcexec "github.com/testcontainers/testcontainers-go/exec"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
)

// memoryPeakFile は、コンテナの中で読む、cgroup v2 のメモリの最大のファイルである。
// コンテナを起動してからの最大なので、同時に送ったときの最大より小さくなることは無い。
const memoryPeakFile = "/sys/fs/cgroup/memory.peak"

// PerfEnv は、応答の時間の比べ方で、1つの版を、その版だけの Postgres と Redis と fakeaws と fakeoidc につないだ環境である。
// Java 版と Go 版を別々のデータベースと Redis につなぎ、一方の版の保存がもう一方の版の時間に響かないようにする。
type PerfEnv struct {
	*Stack
	// URL は、テストの処理から届く backend の URL である。
	URL string

	backend *Container
	client  *http.Client
}

// StartPerfEnv は、env のネットワークに、Postgres と Redis と fakeaws と fakeoidc と、version の位置に置く be を起動する。
// 版ごとに別の env を渡す。途中で失敗したときは、作った Redis のクライアントを閉じて誤りを返す。コンテナは env が片付ける。
func StartPerfEnv(ctx context.Context, env *Env, images Images, version string, be Backend) (*PerfEnv, error) {
	stack, err := startStack(ctx, env, images)
	if err != nil {
		return nil, err
	}
	ctr, url, _, err := startBackend(ctx, env, version, be, stack.backing)
	if err == nil {
		err = stack.registerRedirects(ctx)
	}
	if err != nil {
		_ = stack.Close()
		return nil, err
	}
	return &PerfEnv{Stack: stack, URL: url, backend: ctr, client: NewHTTPClient()}, nil
}

// MemoryPeak は、backend のコンテナの、起動してからのメモリの最大(バイト)を返す。
func (p *PerfEnv) MemoryPeak(ctx context.Context) (uint64, error) {
	code, out, err := p.backend.Exec(ctx, []string{"cat", memoryPeakFile}, tcexec.Multiplexed())
	if err != nil {
		return 0, fmt.Errorf("harness: コンテナ %s の %s を読めません: %w", p.backend.Name, memoryPeakFile, err)
	}
	b, err := io.ReadAll(io.LimitReader(out, 4096))
	if err != nil {
		return 0, fmt.Errorf("harness: コンテナ %s の %s を読めません: %w", p.backend.Name, memoryPeakFile, err)
	}
	if code != 0 {
		return 0, fmt.Errorf("harness: コンテナ %s の %s を読めません(終了の値 %d): %s", p.backend.Name, memoryPeakFile, code, b)
	}
	return parseMemoryPeak(b)
}

// parseMemoryPeak は、memory.peak の中身の、バイトの数を読む。
func parseMemoryPeak(b []byte) (uint64, error) {
	v, err := strconv.ParseUint(strings.TrimSpace(string(b)), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("harness: メモリの最大 %q を数として読めません: %w", b, err)
	}
	return v, nil
}

// RunPerf は、筋書きごとに、Java 版と Go 版の順に、保存された内容を空にして初めのデータを読み込み、
// 最後の段の応答の時間を測って95パーセンタイルを比べる。筋書きの MeasureMemory が true なら、続けて Go 版に最後の段を
// 同時に opts.Concurrency 件送り、Go 版のコンテナのメモリの最大を測る。envs は、版の名前ごとの環境である。
// 環境を整えられないときと、期待に合わない応答があったときは、誤りを返す。
func RunPerf(ctx context.Context, envs map[string]*PerfEnv, scenarios []Scenario, opts PerfOptions) (PerfReport, error) {
	var report PerfReport
	for _, version := range []string{VersionJava, VersionGo} {
		if envs[version] == nil {
			return report, fmt.Errorf("harness: 版 %s の環境がありません", version)
		}
	}
	for _, s := range scenarios {
		result := LatencyResult{Operation: s.Name}
		for _, version := range []string{VersionJava, VersionGo} {
			p95, err := envs[version].measure(ctx, s, opts)
			if err != nil {
				return report, fmt.Errorf("harness: 筋書き %s を版 %s で測れません: %w", s.Name, version, err)
			}
			if version == VersionJava {
				result.Java = p95
			} else {
				result.Go = p95
			}
		}
		report.Latencies = append(report.Latencies, result)
		if s.MeasureMemory {
			goEnv := envs[VersionGo]
			peak, err := goEnv.measurePeak(ctx, s, opts)
			if err != nil {
				return report, fmt.Errorf("harness: 筋書き %s のメモリの最大を測れません: %w", s.Name, err)
			}
			report.Memories = append(report.Memories, MemoryResult{Operation: s.Name, PeakBytes: peak})
		}
	}
	return report, nil
}

// measure は、保存された内容を空にして筋書き s の初めのデータを読み込み、最後の段の95パーセンタイルを返す。
// prepare_each が真の筋書きでは、measureLatency が回ごとに準備の段を送り直し、最後の段の時間だけを測る。
// 測る前に fakeoidc を初めの状態に戻して oidc_users の利用者を登録し、測ったあとに、失敗したときも、初めの状態に戻す。
func (p *PerfEnv) measure(ctx context.Context, s Scenario, opts PerfOptions) (time.Duration, error) {
	if err := p.Reset(ctx); err != nil {
		return 0, err
	}
	if err := LoadFixtures(ctx, p.DBConn, s.Fixtures); err != nil {
		return 0, err
	}
	var samples []time.Duration
	err := p.withOIDC(ctx, s.OIDCUsers, func() (err error) {
		samples, err = measureLatency(ctx, p.stepTools(), p.URL, s, opts.Warmup, opts.Samples)
		return err
	})
	if err != nil {
		return 0, err
	}
	return Percentile95(samples)
}

// measurePeak は、筋書き s の最後の段を同時に opts.Concurrency 件送ったときの、backend のコンテナのメモリの最大を返す。
// measure と同じく、fakeoidc を初めの状態に戻して oidc_users の利用者を登録し、終わりに初めの状態に戻す。
func (p *PerfEnv) measurePeak(ctx context.Context, s Scenario, opts PerfOptions) (uint64, error) {
	var peak uint64
	err := p.withOIDC(ctx, s.OIDCUsers, func() (err error) {
		peak, err = measureConcurrentPeak(ctx, p.stepTools(), p.URL, s, opts.Concurrency, p.MemoryPeak)
		return err
	})
	return peak, err
}

// stepTools は、この環境の Redis と、fakeaws の版によらない記録のメールと、版の AWS の接続先で段を動かす道具を返す。
func (p *PerfEnv) stepTools() stepTools {
	return p.tools(p.client, p.Redis, fakeaws.SharedVersion, p.backing.AWSEndpoint)
}
