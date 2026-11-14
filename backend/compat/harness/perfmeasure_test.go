//go:build compat

package harness

import (
	"context"
	"errors"
	"maps"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestPercentile95(t *testing.T) {
	ms := func(values ...int) []time.Duration {
		var out []time.Duration
		for _, v := range values {
			out = append(out, time.Duration(v)*time.Millisecond)
		}
		return out
	}
	// 200 個の 1〜200ms を逆の順に並べる。短いほうから190番目は 190ms である。
	var reversed []int
	for v := 200; v >= 1; v-- {
		reversed = append(reversed, v)
	}
	for name, tc := range map[string]struct {
		samples []time.Duration
		want    time.Duration
	}{
		"200個":       {ms(reversed...), 190 * time.Millisecond},
		"1個":         {ms(7), 7 * time.Millisecond},
		"切り上げる位置":    {ms(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11), 11 * time.Millisecond},
		"95%ちょうどの位置": {ms(20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1), 19 * time.Millisecond},
	} {
		before := append([]time.Duration(nil), tc.samples...)
		got, err := Percentile95(tc.samples)
		if err != nil || got != tc.want {
			t.Errorf("%s: Percentile95 = %v, %v, want %v", name, got, err, tc.want)
		}
		for i := range before {
			if tc.samples[i] != before[i] {
				t.Errorf("%s: 渡した時間の並びを変えました", name)
				break
			}
		}
	}
	if _, err := Percentile95(nil); err == nil {
		t.Error("測った時間が無いのに誤りを返しませんでした")
	}
}

// perfScenario は、ログインして Cookie を受けたあと、/work を測る筋書きである。
func perfScenario(workStatus int) Scenario {
	return Scenario{Name: "work", Modes: []string{ModePerf}, Steps: []Step{
		{Name: "login", Request: Request{Method: http.MethodPost, Path: "/login"}, Expect: Expect{Status: http.StatusOK}},
		{Name: "work", Request: Request{Method: http.MethodGet, Path: "/work"}, Expect: Expect{Status: workStatus}},
	}}
}

func loginThenWork(delay time.Duration) func(w http.ResponseWriter, r *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/login":
			w.Header().Add("Set-Cookie", "session=s1; Path=/")
		case "/work":
			time.Sleep(delay)
			if r.Header.Get("Cookie") != "session=s1" {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
		}
		_, _ = w.Write([]byte("{}"))
	}
}

func TestMeasureLatency_WarmsUpThenTimesLastStep(t *testing.T) {
	const delay = 5 * time.Millisecond
	srv, reqs := recordingServer(t, loginThenWork(delay))
	samples, err := MeasureLatency(t.Context(), NewHTTPClient(), srv.URL, perfScenario(http.StatusOK), 3, 7)
	if err != nil {
		t.Fatalf("MeasureLatency: %v", err)
	}
	if len(samples) != 7 {
		t.Fatalf("測った時間の数 = %d, want 7", len(samples))
	}
	for i, d := range samples {
		if d < delay {
			t.Errorf("%d 回目の時間 %v が、応答にかかる %v より短い", i+1, d, delay)
		}
	}
	var paths []string
	for _, r := range reqs() {
		paths = append(paths, r.Path)
	}
	want := "/login" + strings.Repeat(" /work", 10)
	if got := strings.Join(paths, " "); got != want {
		t.Errorf("送った要求 = %s, want %s", got, want)
	}
}

func TestMeasureLatency_FailsOnUnexpectedResponse(t *testing.T) {
	for name, tc := range map[string]struct {
		s        Scenario
		handle   func(w http.ResponseWriter, r *http.Request)
		wantStep string
	}{
		"準備の段": {perfScenario(http.StatusOK), func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusForbidden)
		}, "login"},
		"測る段": {perfScenario(http.StatusCreated), loginThenWork(0), "work"},
		"測る段の途中": {perfScenario(http.StatusOK), func() func(http.ResponseWriter, *http.Request) {
			var mu sync.Mutex
			n := 0
			return func(w http.ResponseWriter, r *http.Request) {
				mu.Lock()
				n++
				fail := n == 4
				mu.Unlock()
				if fail {
					w.WriteHeader(http.StatusInternalServerError)
				}
			}
		}(), "work"},
	} {
		srv, _ := recordingServer(t, tc.handle)
		_, err := MeasureLatency(t.Context(), NewHTTPClient(), srv.URL, tc.s, 1, 5)
		if err == nil || !strings.Contains(err.Error(), "段 "+tc.wantStep) {
			t.Errorf("%s: 誤り = %v, want 段 %s の誤り", name, err, tc.wantStep)
		}
	}
	if _, err := MeasureLatency(t.Context(), NewHTTPClient(), "http://127.0.0.1:1", Scenario{Name: "empty"}, 1, 1); err == nil {
		t.Error("段の無い筋書きで誤りを返しませんでした")
	}
}

// prepareEachScenario は、ログインして確認のコードを受けたあと、そのコードを付けて /verify を測る筋書きである。
// 確認のコードは1回使うと消えるので、prepare_each を真にする。
func prepareEachScenario() Scenario {
	return Scenario{Name: "verify", Modes: []string{ModePerf}, PrepareEach: true, Steps: []Step{
		{Name: "login", Request: Request{Method: http.MethodPost, Path: "/login"}, Expect: Expect{Status: http.StatusOK}},
		{
			Name: "challenge", Request: Request{Method: http.MethodPost, Path: "/challenge"},
			Capture: map[string]string{"code": "$.code"}, Expect: Expect{Status: http.StatusOK},
		},
		{
			Name: "verify", Request: Request{Method: http.MethodPost, Path: "/verify", Headers: map[string]string{"X-Code": "{code}"}},
			Expect: Expect{Status: http.StatusOK},
		},
	}}
}

// oneTimeCodes は、ログインのたびに新しい Cookie を、確認のコードを求めるたびに新しいコードを渡し、
// /verify では、いちばん新しい Cookie とコードの組を1回だけ受けるサーバの処理である。ログインには loginDelay、
// 確認のコードには challengeDelay、/verify には verifyDelay だけかける。failLoginAt 回目のログインは 500 で答える。
func oneTimeCodes(loginDelay, challengeDelay, verifyDelay time.Duration, failLoginAt int) func(w http.ResponseWriter, r *http.Request) {
	var mu sync.Mutex
	logins, codes := 0, 0
	used := true
	return func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		switch r.URL.Path {
		case "/login":
			time.Sleep(loginDelay)
			logins++
			if logins == failLoginAt {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			w.Header().Add("Set-Cookie", "session=s"+strconv.Itoa(logins)+"; Path=/")
			_, _ = w.Write([]byte("{}"))
		case "/challenge":
			time.Sleep(challengeDelay)
			codes++
			used = false
			_, _ = w.Write([]byte(`{"code":"c` + strconv.Itoa(codes) + `"}`))
		case "/verify":
			time.Sleep(verifyDelay)
			if used || r.Header.Get("Cookie") != "session=s"+strconv.Itoa(logins) || r.Header.Get("X-Code") != "c"+strconv.Itoa(codes) {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			used = true
			_, _ = w.Write([]byte("{}"))
		}
	}
}

func TestMeasureLatency_PrepareEach(t *testing.T) {
	t.Run("慣らしの回と測る回のそれぞれの前に、最後の段より前の段を送り直す", func(t *testing.T) {
		srv, reqs := recordingServer(t, oneTimeCodes(0, 0, 0, 0))
		samples, err := MeasureLatency(t.Context(), NewHTTPClient(), srv.URL, prepareEachScenario(), 2, 3)
		if err != nil {
			t.Fatalf("MeasureLatency: %v", err)
		}
		if len(samples) != 3 {
			t.Fatalf("測った時間の数 = %d, want 3", len(samples))
		}
		var paths []string
		for _, r := range reqs() {
			paths = append(paths, r.Path)
		}
		want := strings.TrimSpace(strings.Repeat("/login /challenge /verify ", 5))
		if got := strings.Join(paths, " "); got != want {
			t.Errorf("送った要求 = %s, want %s", got, want)
		}
	})

	t.Run("最後の段の時間だけを返す", func(t *testing.T) {
		const prepareDelay, verifyDelay = 150 * time.Millisecond, 5 * time.Millisecond
		for name, delays := range map[string][2]time.Duration{
			"ログインの段が遅い":      {prepareDelay, 0},
			"確認のコードを求める段が遅い": {0, prepareDelay},
		} {
			srv, _ := recordingServer(t, oneTimeCodes(delays[0], delays[1], verifyDelay, 0))
			samples, err := MeasureLatency(t.Context(), NewHTTPClient(), srv.URL, prepareEachScenario(), 1, 3)
			if err != nil {
				t.Fatalf("%s: MeasureLatency: %v", name, err)
			}
			for i, d := range samples {
				if d < verifyDelay || d >= prepareDelay {
					t.Errorf("%s: %d 回目の時間 %v は、最後の段にかかる %v 以上で、準備の段にかかる %v より短いはず", name, i+1, d, verifyDelay, prepareDelay)
				}
			}
		}
	})

	t.Run("送り直した準備の段が期待に合わなければ誤りを返す", func(t *testing.T) {
		for name, failAt := range map[string]int{"慣らしの回の前": 2, "測る回の前": 4} {
			srv, _ := recordingServer(t, oneTimeCodes(0, 0, 0, failAt))
			_, err := MeasureLatency(t.Context(), NewHTTPClient(), srv.URL, prepareEachScenario(), 2, 3)
			if err == nil || !strings.Contains(err.Error(), "段 login") {
				t.Errorf("%s: 誤り = %v, want 段 login の誤り", name, err)
			}
		}
	})

	t.Run("prepare_each が偽なら準備の段を1回だけ送る", func(t *testing.T) {
		srv, reqs := recordingServer(t, loginThenWork(0))
		s := perfScenario(http.StatusOK)
		if _, err := MeasureLatency(t.Context(), NewHTTPClient(), srv.URL, s, 2, 3); err != nil {
			t.Fatalf("MeasureLatency: %v", err)
		}
		if n := len(reqs()); n != 6 {
			t.Errorf("送った要求の数 = %d, want 6(準備の段1回と最後の段5回)", n)
		}
	})
}

// barrier は、n 件の要求が届くまで、どの要求にも答えないサーバの処理である。n 件が同時に届かなければ 500 を返す。
func barrier(n int) func(w http.ResponseWriter, r *http.Request) {
	var mu sync.Mutex
	arrived := 0
	all := make(chan struct{})
	return func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/login" {
			w.Header().Add("Set-Cookie", "session=s1; Path=/")
			return
		}
		mu.Lock()
		arrived++
		if arrived == n {
			close(all)
		}
		mu.Unlock()
		select {
		case <-all:
		case <-time.After(5 * time.Second):
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		if r.Header.Get("Cookie") != "session=s1" {
			w.WriteHeader(http.StatusUnauthorized)
		}
	}
}

func TestMeasureConcurrentPeak_SendsInParallelThenReadsPeak(t *testing.T) {
	srv, reqs := recordingServer(t, barrier(2))
	var readAt int
	peak := func(context.Context) (uint64, error) {
		readAt = len(reqs())
		return 1234, nil
	}
	got, err := MeasureConcurrentPeak(t.Context(), NewHTTPClient(), srv.URL, perfScenario(http.StatusOK), 2, peak)
	if err != nil || got != 1234 {
		t.Fatalf("MeasureConcurrentPeak = %d, %v, want 1234", got, err)
	}
	if readAt != 3 {
		t.Errorf("メモリの最大を読んだときの要求の数 = %d, want 3(準備1件と同時の2件)", readAt)
	}
}

func TestMeasureConcurrentPeak_FailsWithoutReadingPeak(t *testing.T) {
	broken := errors.New("読めない")
	for name, tc := range map[string]struct {
		handle func(w http.ResponseWriter, r *http.Request)
		peak   func(context.Context) (uint64, error)
		want   string
	}{
		"期待と違う応答": {func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path == "/work" {
				w.WriteHeader(http.StatusInternalServerError)
			}
		}, func(context.Context) (uint64, error) {
			t.Error("失敗した要求のあとでメモリの最大を読みました")
			return 0, nil
		}, "段 work"},
		"準備の失敗": {
			func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusForbidden) },
			func(context.Context) (uint64, error) {
				t.Error("準備の失敗のあとでメモリの最大を読みました")
				return 0, nil
			}, "段 login",
		},
		"メモリの最大を読めない": {barrier(2), func(context.Context) (uint64, error) { return 0, broken }, "読めない"},
	} {
		srv, _ := recordingServer(t, tc.handle)
		_, err := MeasureConcurrentPeak(t.Context(), NewHTTPClient(), srv.URL, perfScenario(http.StatusOK), 2, tc.peak)
		if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%s: 誤り = %v, want %q を含む誤り", name, err, tc.want)
		}
	}
}

func TestSession_CloneIsIndependent(t *testing.T) {
	s := NewSession()
	s.cookies[cookieKey{"a", "/"}] = "1"
	s.vars["id"] = "x"
	c := s.Clone()
	c.cookies[cookieKey{"b", "/"}] = "2"
	c.vars["id"] = "y"
	if len(s.cookies) != 1 || s.vars["id"] != "x" {
		t.Errorf("写しを変えたら元が変わりました: %v %v", s.cookies, s.vars)
	}
	if c.cookies[cookieKey{"a", "/"}] != "1" || c.now == nil {
		t.Errorf("写しに元の Cookie と時計がありません: %v", c.cookies)
	}
}

func TestParseMemoryPeak(t *testing.T) {
	if got, err := parseMemoryPeak([]byte("1879048192\n")); err != nil || got != 1879048192 {
		t.Errorf("parseMemoryPeak = %d, %v, want 1879048192", got, err)
	}
	for _, bad := range []string{"", "max\n", "-1", "12MB"} {
		if _, err := parseMemoryPeak([]byte(bad)); err == nil {
			t.Errorf("parseMemoryPeak(%q) が誤りを返しませんでした", bad)
		}
	}
}

func TestLoadScenario_PerfFields(t *testing.T) {
	perf := strings.Replace(designScenario, "modes: [compare, cross]", "modes: [perf]\nmeasure_memory: true", 1)
	s, err := LoadScenario(writeScenario(t, perf))
	if err != nil || !s.MeasureMemory {
		t.Fatalf("LoadScenario = %+v, %v, want measure_memory を読む", s, err)
	}
	for name, tc := range map[string]struct {
		content, want string
	}{
		"perf でない筋書きの measure_memory": {strings.Replace(designScenario, "modes: [compare, cross]", "modes: [compare]\nmeasure_memory: true", 1), "measure_memory"},
		"最後の段の status が無い": {strings.Replace(strings.Replace(designScenario, "modes: [compare, cross]", "modes: [perf]", 1),
			"      json: {name: 新しい名前}\n    expect: {status: 200}\n", "      json: {name: 新しい名前}\n", 1), "save-basic"},
	} {
		_, err := LoadScenario(writeScenario(t, tc.content))
		if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%s: 誤り = %v, want %q を含む誤り", name, err, tc.want)
		}
	}
	// 最後でない段は status が無くてもよい
	first := strings.Replace(strings.Replace(designScenario, "modes: [compare, cross]", "modes: [perf]", 1),
		"    capture: {}\n    expect: {status: 200}\n", "    capture: {}\n", 1)
	if _, err := LoadScenario(writeScenario(t, first)); err != nil {
		t.Errorf("最後でない段の status が無い筋書きを断りました: %v", err)
	}
}

// TestLoadScenarios_AuthPerf は、認証の筋書きのうち、応答の時間を測る筋書きが、ログイン、2段階認証の確認、作り直し、
// 新規の登録の4つの操作を最後の段で送ることを確かめる。2段階認証の確認は、確認のコードが1回使うと消えるので、
// 回ごとに準備の段を送り直し、ログインの段のあとに届いたメールからコードを取り出す。メモリの最大はどれも測らない。
func TestLoadScenarios_AuthPerf(t *testing.T) {
	scenarios, err := LoadScenarios(filepath.Join("..", "scenarios", "auth"), ModePerf)
	if err != nil {
		t.Fatalf("LoadScenarios: %v", err)
	}
	type want struct {
		last        string
		steps       int
		prepareEach bool
	}
	wants := map[string]want{
		"auth-login-perf":      {"POST /api/auth/login", 1, false},
		"auth-two-factor-perf": {"POST /api/auth/2fa/verify", 2, true},
		"auth-refresh-perf":    {"POST /api/auth/token/refresh", 2, false},
		"auth-register-perf":   {"POST /api/auth/register", 1, false},
	}
	got := map[string]Scenario{}
	for _, s := range scenarios {
		got[s.Name] = s
	}
	if len(got) != len(wants) {
		t.Errorf("測る筋書きの数 = %d, want %d(読んだ筋書きは %v)", len(got), len(wants), slices.Sorted(maps.Keys(got)))
	}
	for name, w := range wants {
		s, ok := got[name]
		if !ok {
			t.Errorf("測る筋書き %s がありません", name)
			continue
		}
		if len(s.Steps) != w.steps {
			t.Errorf("筋書き %s の段の数 = %d, want %d", name, len(s.Steps), w.steps)
			continue
		}
		last := s.Steps[len(s.Steps)-1]
		if op := last.Request.Method + " " + last.Request.Path; op != w.last {
			t.Errorf("筋書き %s の最後の段 = %s, want %s", name, op, w.last)
		}
		if s.PrepareEach != w.prepareEach {
			t.Errorf("筋書き %s の prepare_each = %v, want %v", name, s.PrepareEach, w.prepareEach)
		}
		if s.MeasureMemory {
			t.Errorf("筋書き %s が measure_memory を持ちます。メモリの最大は PDF の出力の筋書きだけで測ります", name)
		}
	}
	if s, ok := got["auth-two-factor-perf"]; ok && len(s.Steps) == 2 {
		login, verify := s.Steps[0], s.Steps[1]
		if login.Request.Path != "/api/auth/login" || jsonField(login.Request.JSON, "email") != "twofactor@example.com" {
			t.Errorf("2段階認証の確認の準備の段 = %s %v, want 2段階認証を有効にした利用者 twofactor@example.com のログイン",
				login.Request.Path, login.Request.JSON)
		}
		capture := login.Capture["code"]
		if !strings.HasPrefix(capture, "mail:") {
			t.Errorf("2段階認証の確認のコードの取り出し = %q, want mail: から始まる取り出し", capture)
		}
		if code := jsonField(verify.Request.JSON, "code"); code != "{code}" {
			t.Errorf("2段階認証の確認の段のコード = %v, want 取り出した {code}", code)
		}
	}
}

// TestLoadScenarios_UsersPerf は、利用者の操作の筋書きのうち、応答の時間を測る筋書きが、ログインの段のあとに、
// 利用者の情報を見る段と、名前を変える段を、最後の段で送ることを確かめる。名前を変える段は、毎回同じ名前の部分だけを送る。
// どちらも回ごとに準備の段を送り直さず、メモリの最大を測らない。
func TestLoadScenarios_UsersPerf(t *testing.T) {
	scenarios, err := LoadScenarios(filepath.Join("..", "scenarios", "users"), ModePerf)
	if err != nil {
		t.Fatalf("LoadScenarios: %v", err)
	}
	wants := map[string]string{
		"users-get-user-info-perf":   "GET /api/users/me",
		"users-update-username-perf": "PUT /api/users/me",
	}
	got := map[string]Scenario{}
	for _, s := range scenarios {
		got[s.Name] = s
	}
	if len(got) != len(wants) {
		t.Errorf("測る筋書きの数 = %d, want %d(読んだ筋書きは %v)", len(got), len(wants), slices.Sorted(maps.Keys(got)))
	}
	for name, op := range wants {
		s, ok := got[name]
		if !ok {
			t.Errorf("測る筋書き %s がありません", name)
			continue
		}
		if len(s.Steps) != 2 {
			t.Errorf("筋書き %s の段の数 = %d, want 2", name, len(s.Steps))
			continue
		}
		login, last := s.Steps[0], s.Steps[1]
		if login.Request.Method+" "+login.Request.Path != "POST /api/auth/login" ||
			jsonField(login.Request.JSON, "email") != "user1@example.com" {
			t.Errorf("筋書き %s の準備の段 = %s %s %v, want user1@example.com のログイン",
				name, login.Request.Method, login.Request.Path, login.Request.JSON)
		}
		if got := last.Request.Method + " " + last.Request.Path; got != op {
			t.Errorf("筋書き %s の最後の段 = %s, want %s", name, got, op)
		}
		if s.PrepareEach || s.MeasureMemory {
			t.Errorf("筋書き %s の prepare_each = %v、measure_memory = %v, want どちらも偽", name, s.PrepareEach, s.MeasureMemory)
		}
	}
	if s, ok := got["users-update-username-perf"]; ok && len(s.Steps) == 2 {
		parts := s.Steps[1].Request.Multipart
		if len(parts) != 1 || parts[0].Name != "username" || parts[0].Value == nil ||
			*parts[0].Value == "" || strings.Contains(*parts[0].Value, "{") || !s.Steps[1].Request.CSRF {
			t.Errorf("名前を変える段の部分 = %+v、csrf = %v, want 置き換えの無い同じ名前の username の部分1つと csrf",
				parts, s.Steps[1].Request.CSRF)
		}
	}
}

func TestWritePerfReport(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "report")
	report := PerfReport{Latencies: []LatencyResult{{Operation: "login", Java: time.Millisecond, Go: time.Millisecond}}}
	file, err := report.Write(dir)
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	if file != filepath.Join(dir, "perf.txt") {
		t.Errorf("書いたファイル = %s", file)
	}
	b, err := os.ReadFile(filepath.Clean(file))
	if err != nil || string(b) != report.String() {
		t.Errorf("書いた中身 = %q, %v, want %q", b, err, report.String())
	}
	blocked := filepath.Join(t.TempDir(), "file")
	if err := os.WriteFile(blocked, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := report.Write(filepath.Join(blocked, "sub")); err == nil {
		t.Error("フォルダを作れないのに誤りを返しませんでした")
	}
}

// jsonField は、段の本文 body が項目の並びなら、項目 key の値を返す。項目の並びでなければ nil を返す。
func jsonField(body any, key string) any {
	fields, ok := body.(map[string]any)
	if !ok {
		return nil
	}
	return fields[key]
}
