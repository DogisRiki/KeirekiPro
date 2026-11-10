//go:build compat

package harness

import (
	"strings"
	"testing"
	"time"
)

// 要件9の受入基準7: Go 版の95パーセンタイルが「Java 版 × 1.2 + 20ミリ秒」の内側なら通す。
func TestPerfJudge_WithinTolerance(t *testing.T) {
	for name, tc := range map[string]struct {
		java, goP95, limit time.Duration
	}{
		"上限と同じ時間":    {100 * time.Millisecond, 140 * time.Millisecond, 140 * time.Millisecond},
		"Go 版のほうが速い": {100 * time.Millisecond, 60 * time.Millisecond, 140 * time.Millisecond},
		"数ミリ秒の操作の揺れ": {2 * time.Millisecond, 22*time.Millisecond + 400*time.Microsecond, 22*time.Millisecond + 400*time.Microsecond},
	} {
		r := LatencyResult{Operation: "login", Java: tc.java, Go: tc.goP95}
		if got := r.Limit(); got != tc.limit {
			t.Errorf("%s: 上限 = %v, want %v", name, got, tc.limit)
		}
		if !r.Within() {
			t.Errorf("%s: Java 版 %v、Go 版 %v を、上限を超えたとしました", name, tc.java, tc.goP95)
		}
		report := PerfReport{Latencies: []LatencyResult{r}}
		if report.Failed() {
			t.Errorf("%s: 上限の内側の結果を失敗にしました:\n%s", name, report)
		}
		if s := report.String(); !strings.Contains(s, "上限の内側です") || strings.Contains(s, "超え") {
			t.Errorf("%s: 報告 = %q", name, s)
		}
	}
}

// 要件9の受入基準7: Go 版の95パーセンタイルが上限を超えた操作があれば失敗にし、操作と測った値を報告に書く。
func TestPerfJudge_ExceedsTolerance(t *testing.T) {
	report := PerfReport{Latencies: []LatencyResult{
		{Operation: "login", Java: 10 * time.Millisecond, Go: 12 * time.Millisecond},
		{Operation: "pdf-export", Java: 100 * time.Millisecond, Go: 140*time.Millisecond + time.Microsecond},
	}}
	if report.Latencies[0].Within() != true || report.Latencies[1].Within() != false {
		t.Errorf("判定 = %v %v, want true false", report.Latencies[0].Within(), report.Latencies[1].Within())
	}
	if !report.Failed() {
		t.Fatalf("上限を超えた操作があるのに失敗にしませんでした:\n%s", report)
	}
	s := report.String()
	for _, want := range []string{
		"上限を超えた操作があります",
		"操作 pdf-export: 95パーセンタイルは Java 版 100.0ms、Go 版 140.0ms。Go 版の上限は 140.0ms。上限を超えました",
		"操作 login: 95パーセンタイルは Java 版 10.0ms、Go 版 12.0ms。Go 版の上限は 32.0ms。上限の内側です",
	} {
		if !strings.Contains(s, want) {
			t.Errorf("報告に %q がありません:\n%s", want, s)
		}
	}
}

// 要件9の受入基準7: PDF の出力を同時に2件送ったときの Go 版のメモリの最大が 1792MB を超えたら失敗にする。
func TestPerfJudge_MemoryOver1792MBFails(t *testing.T) {
	latency := LatencyResult{Operation: "pdf-export", Java: 100 * time.Millisecond, Go: 100 * time.Millisecond}
	at := PerfReport{Latencies: []LatencyResult{latency}, Memories: []MemoryResult{{Operation: "pdf-export", PeakBytes: 1792 << 20}}}
	if at.Failed() {
		t.Errorf("1792MB ちょうどを失敗にしました:\n%s", at)
	}
	over := PerfReport{Latencies: []LatencyResult{latency}, Memories: []MemoryResult{{Operation: "pdf-export", PeakBytes: 1792<<20 + 1}}}
	if !over.Failed() {
		t.Fatalf("1792MB を超えたのに失敗にしませんでした:\n%s", over)
	}
	want := "操作 pdf-export: 同時に 2 件送ったときの Go 版のコンテナのメモリの最大は 1792.0MB。上限は 1792.0MB。上限を超えました"
	if s := over.String(); !strings.Contains(s, want) || !strings.Contains(s, "上限を超えた操作があります") {
		t.Errorf("報告に %q がありません:\n%s", want, s)
	}
}
