//go:build compat

package harness

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"
)

// 応答の時間の比べ方の値である。design.md の「perf(応答の時間の比べ方)」で決めた。
const (
	// PerfWarmup は、測る前に送る、時間を測らない要求の数である。
	PerfWarmup = 20
	// PerfSamples は、時間を測る要求の数である。1つずつ順に送る。
	PerfSamples = 200
	// PerfConcurrency は、メモリの最大を測るときに、同時に送る要求の数である。本番の PDF の同時の数と同じにする。
	PerfConcurrency = 2
	// PerfSlack は、許す幅の割合に足す時間である。Java 版の応答が数ミリ秒の操作で、測るたびの揺れだけで割合の幅を超えないようにする。
	PerfSlack = 20 * time.Millisecond
	// MemoryLimitBytes は、Go 版のコンテナのメモリの最大の上限である。タスク定義の memoryReservation 1792MB に当たる。
	MemoryLimitBytes uint64 = 1792 << 20
)

// PerfOptions は、1つの操作で送る要求の数である。
type PerfOptions struct {
	Warmup, Samples, Concurrency int
}

// DefaultPerfOptions は、design.md で決めた要求の数である。
var DefaultPerfOptions = PerfOptions{Warmup: PerfWarmup, Samples: PerfSamples, Concurrency: PerfConcurrency}

// Percentile95 は、測った時間の95パーセンタイルを返す。測った時間を短い順に並べ、短いほうから数えて
// 測った数の95%(小数は切り上げる)番目の時間である。測った時間が無いときは誤りを返す。
func Percentile95(samples []time.Duration) (time.Duration, error) {
	if len(samples) == 0 {
		return 0, errors.New("harness: 95パーセンタイルを求める、測った時間がありません")
	}
	sorted := slices.Clone(samples)
	slices.Sort(sorted)
	rank := (len(sorted)*95 + 99) / 100
	return sorted[rank-1], nil
}

// LatencyLimit は、Java 版の95パーセンタイルから、Go 版の95パーセンタイルの上限「Java 版 × 1.2 + 20ミリ秒」を返す。
func LatencyLimit(java time.Duration) time.Duration {
	return java + java/5 + PerfSlack
}

// LatencyResult は、1つの操作の、Java 版と Go 版の95パーセンタイルである。
type LatencyResult struct {
	Operation string
	Java, Go  time.Duration
}

// Limit は、この操作の Go 版の95パーセンタイルの上限である。
func (r LatencyResult) Limit() time.Duration { return LatencyLimit(r.Java) }

// Within は、Go 版の95パーセンタイルが上限の内側にあるかを返す。上限と同じ時間は内側とする。
func (r LatencyResult) Within() bool { return r.Go <= r.Limit() }

// MemoryResult は、1つの操作を同時に送ったときの、Go 版のコンテナのメモリの最大である。
type MemoryResult struct {
	Operation string
	PeakBytes uint64
}

// Within は、メモリの最大が MemoryLimitBytes の内側にあるかを返す。上限と同じ値は内側とする。
func (r MemoryResult) Within() bool { return r.PeakBytes <= MemoryLimitBytes }

// PerfReport は、応答の時間の比べ方の結果である。
type PerfReport struct {
	Latencies []LatencyResult
	Memories  []MemoryResult
}

// Failed は、上限を超えた操作が1つでもあるかを返す。
func (r PerfReport) Failed() bool {
	return slices.ContainsFunc(r.Latencies, func(l LatencyResult) bool { return !l.Within() }) ||
		slices.ContainsFunc(r.Memories, func(m MemoryResult) bool { return !m.Within() })
}

// String は、操作ごとの測った値と上限と判定を、人が読める文にする。
func (r PerfReport) String() string {
	var b strings.Builder
	verdict := "上限の内側です"
	if r.Failed() {
		verdict = "上限を超えた操作があります"
	}
	fmt.Fprintf(&b, "応答の時間の比べ方: %s\n", verdict)
	for _, l := range r.Latencies {
		fmt.Fprintf(&b, "  操作 %s: 95パーセンタイルは Java 版 %s、Go 版 %s。Go 版の上限は %s。%s\n",
			l.Operation, formatMillis(l.Java), formatMillis(l.Go), formatMillis(l.Limit()), judgeText(l.Within()))
	}
	for _, m := range r.Memories {
		fmt.Fprintf(&b, "  操作 %s: 同時に %d 件送ったときの Go 版のコンテナのメモリの最大は %s。上限は %s。%s\n",
			m.Operation, PerfConcurrency, formatMB(m.PeakBytes), formatMB(MemoryLimitBytes), judgeText(m.Within()))
	}
	return b.String()
}

func judgeText(within bool) string {
	if within {
		return "上限の内側です"
	}
	return "上限を超えました"
}

func formatMillis(d time.Duration) string {
	return fmt.Sprintf("%.1fms", float64(d)/float64(time.Millisecond))
}

func formatMB(bytes uint64) string {
	return fmt.Sprintf("%.1fMB", float64(bytes)/(1<<20))
}

// Write は、報告を dir の perf.txt に書き、書いたファイルのパスを返す。
func (r PerfReport) Write(dir string) (string, error) {
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return "", fmt.Errorf("harness: 報告のフォルダ %s を作れません: %w", dir, err)
	}
	file := filepath.Join(dir, "perf.txt")
	if err := os.WriteFile(file, []byte(r.String()), 0o600); err != nil {
		return "", fmt.Errorf("harness: 報告 %s を書けません: %w", file, err)
	}
	return file, nil
}

// prepare は、筋書き s の最後の段より前の段を、1回ずつ順に tools で動かし、動かしたあとの Session を返す。
// 最後の段より前の段は、ログインのような、測る操作の準備である。応答が期待に合わない段があれば誤りを返す。
func prepare(ctx context.Context, tools stepTools, baseURL string, s Scenario) (*Session, error) {
	if len(s.Steps) == 0 {
		return nil, fmt.Errorf("harness: 筋書き %s に、測る段がありません", s.Name)
	}
	if last := s.Steps[len(s.Steps)-1]; last.Kind() != StepVersion {
		return nil, fmt.Errorf("harness: 筋書き %s の測る最後の段 %s は、版に送る段でなければなりません", s.Name, last.Name)
	}
	session := tools.newSession()
	for _, step := range s.Steps[:len(s.Steps)-1] {
		if err := sendExpect(ctx, tools, session, baseURL, step); err != nil {
			return nil, err
		}
	}
	return session, nil
}

// sendExpect は、段 step を tools で動かし、応答が期待に合わなければ誤りを返す。
// 絶対の URL の段の expect の status は、SendAbsolute が確かめて誤りを返す。要求を送らない段には expect が無い。
func sendExpect(ctx context.Context, tools stepTools, session *Session, baseURL string, step Step) error {
	resp, err := tools.send(ctx, session, baseURL, step)
	if err != nil {
		return err
	}
	if problems := checkStepExpect(session, step, resp); len(problems) > 0 {
		return fmt.Errorf("harness: 段 %s の応答が期待と違います: %s", step.Name, strings.Join(problems, "。"))
	}
	return nil
}

// MeasureLatency は、筋書き s の準備の段を送ったあと、最後の段を、時間を測らずに warmup 回、時間を測って samples 回、
// 1つずつ順に baseURL に送り、測った時間を返す。時間は、要求を送ってから応答の本文を読み終えるまでである。
// s.PrepareEach が真なら、慣らしの回と測る回のそれぞれの前に、準備の段を新しい Session で送り直す。
// 確認のコードのような、1回使うと消える値を最後の段で使う操作を測るためである。準備の段の時間は測らない。
// 期待に合わない応答があれば、誤りを返す。失敗の応答の時間を測っても、操作の時間を比べたことにならないためである。
// Redis もメールも fakeoidc も持たないので、それらを使う準備の段は、誤りになる。
func MeasureLatency(ctx context.Context, client *http.Client, baseURL string, s Scenario, warmup, samples int) ([]time.Duration, error) {
	return measureLatency(ctx, stepTools{client: client}, baseURL, s, warmup, samples)
}

// measureLatency は、MeasureLatency の測り方で、準備の段を tools で動かす。最後の段は版に送る段である。
func measureLatency(ctx context.Context, tools stepTools, baseURL string, s Scenario, warmup, samples int) ([]time.Duration, error) {
	session, err := prepare(ctx, tools, baseURL, s)
	if err != nil {
		return nil, err
	}
	// round は、i 回目(慣らしの回から数える)の最後の段を送る Session を返す
	round := func(i int) (*Session, error) {
		if !s.PrepareEach || i == 0 {
			return session, nil
		}
		return prepare(ctx, tools, baseURL, s)
	}
	last := s.Steps[len(s.Steps)-1]
	for i := range warmup {
		sess, err := round(i)
		if err != nil {
			return nil, err
		}
		if err := sendExpect(ctx, tools, sess, baseURL, last); err != nil {
			return nil, err
		}
	}
	durations := make([]time.Duration, 0, samples)
	for i := range samples {
		sess, err := round(warmup + i)
		if err != nil {
			return nil, err
		}
		start := time.Now()
		resp, err := sess.Send(ctx, tools.client, baseURL, last)
		elapsed := time.Since(start)
		if err != nil {
			return nil, err
		}
		if problems := checkStepExpect(sess, last, resp); len(problems) > 0 {
			return nil, fmt.Errorf("harness: 段 %s の応答が期待と違います: %s", last.Name, strings.Join(problems, "。"))
		}
		durations = append(durations, elapsed)
	}
	return durations, nil
}

// MeasureConcurrentPeak は、筋書き s の準備の段を送ったあと、最後の段を、同じ利用者として同時に n 件 baseURL に送り、
// すべての応答を受けてから peak でコンテナのメモリの最大を読んで返す。期待に合わない応答があれば、誤りを返す。
func MeasureConcurrentPeak(ctx context.Context, client *http.Client, baseURL string, s Scenario, n int,
	peak func(context.Context) (uint64, error),
) (uint64, error) {
	return measureConcurrentPeak(ctx, stepTools{client: client}, baseURL, s, n, peak)
}

// measureConcurrentPeak は、MeasureConcurrentPeak の測り方で、準備の段を tools で動かす。
func measureConcurrentPeak(ctx context.Context, tools stepTools, baseURL string, s Scenario, n int,
	peak func(context.Context) (uint64, error),
) (uint64, error) {
	session, err := prepare(ctx, tools, baseURL, s)
	if err != nil {
		return 0, err
	}
	last := s.Steps[len(s.Steps)-1]
	errs := make([]error, n)
	var wg sync.WaitGroup
	for i := range n {
		clone := session.Clone()
		wg.Go(func() { errs[i] = sendExpect(ctx, tools, clone, baseURL, last) })
	}
	wg.Wait()
	if err := errors.Join(errs...); err != nil {
		return 0, err
	}
	return peak(ctx)
}
