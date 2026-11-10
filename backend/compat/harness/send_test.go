//go:build compat

package harness

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"
)

// recorded は、記録するサーバが受けた1つの要求である。
type recorded struct {
	Method, Path, Cookie, CSRF, ContentType, Body string
}

// recordingServer は、受けた要求を記録し、handle が返す応答を返すサーバである。
func recordingServer(t *testing.T, handle func(w http.ResponseWriter, r *http.Request)) (*httptest.Server, func() []recorded) {
	t.Helper()
	var mu sync.Mutex
	var reqs []recorded
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body := new(strings.Builder)
		if r.Body != nil {
			buf := make([]byte, 4096)
			n, _ := r.Body.Read(buf)
			body.Write(buf[:n])
		}
		mu.Lock()
		reqs = append(reqs, recorded{
			Method: r.Method, Path: r.URL.Path, Cookie: r.Header.Get("Cookie"),
			CSRF: r.Header.Get(csrfHeader), ContentType: r.Header.Get("Content-Type"), Body: body.String(),
		})
		mu.Unlock()
		handle(w, r)
	}))
	t.Cleanup(srv.Close)
	return srv, func() []recorded {
		mu.Lock()
		defer mu.Unlock()
		return append([]recorded(nil), reqs...)
	}
}

func get(name, path string) Step {
	return Step{Name: name, Request: Request{Method: http.MethodGet, Path: path}}
}

func TestSession_SendsCookiesForPathAndForgetsDeleted(t *testing.T) {
	srv, reqs := recordingServer(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/set":
			w.Header().Add("Set-Cookie", "root=1; Path=/")
			w.Header().Add("Set-Cookie", "api=2; Path=/api")
			w.Header().Add("Set-Cookie", "other=3; Path=/other")
			w.Header().Add("Set-Cookie", "nopath=4")
		case "/api/delete":
			w.Header().Add("Set-Cookie", "api=; Path=/api; Max-Age=0")
			w.Header().Add("Set-Cookie", "root=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT")
		}
	})
	s := NewSession()
	ctx := t.Context()
	for _, step := range []Step{get("set", "/set"), get("api", "/api/x"), get("apix", "/apix"), get("delete", "/api/delete"), get("after", "/api/x")} {
		if _, err := s.Send(ctx, srv.Client(), srv.URL, step); err != nil {
			t.Fatalf("段 %s: %v", step.Name, err)
		}
	}
	got := reqs()
	// パスの長い Cookie から送る。/apix は /api の Cookie に当たらない
	want := []string{"", "api=2; nopath=4; root=1", "nopath=4; root=1", "api=2; nopath=4; root=1", "nopath=4"}
	for i, r := range got {
		if r.Cookie != want[i] {
			t.Errorf("%d 番目の要求 %s の Cookie = %q, want %q", i+1, r.Path, r.Cookie, want[i])
		}
	}
}

func TestSession_CSRFCopiesCookieToHeader(t *testing.T) {
	srv, reqs := recordingServer(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/token" {
			w.Header().Add("Set-Cookie", csrfCookie+"=tok-1; Path=/")
		}
	})
	s := NewSession()
	post := Step{Name: "post", Request: Request{Method: http.MethodPost, Path: "/api/x", CSRF: true, JSON: map[string]any{"a": 1}}}
	if _, err := s.Send(t.Context(), srv.Client(), srv.URL, post); err == nil || !strings.Contains(err.Error(), csrfCookie) {
		t.Fatalf("Cookie が無いのに csrf の段を送りました: %v", err)
	}
	if n := len(reqs()); n != 0 {
		t.Fatalf("Cookie が無い csrf の段で %d 件の要求を送りました", n)
	}
	if _, err := s.Send(t.Context(), srv.Client(), srv.URL+"/", get("token", "/token")); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Send(t.Context(), srv.Client(), srv.URL, post); err != nil {
		t.Fatal(err)
	}
	last := reqs()[1]
	if last.CSRF != "tok-1" || last.ContentType != "application/json" || last.Body != `{"a":1}` || last.Method != http.MethodPost {
		t.Errorf("csrf の段の要求 = %+v, want ヘッダ tok-1 と JSON の本文", last)
	}
	plain := reqs()[0]
	if plain.CSRF != "" || plain.ContentType != "" {
		t.Errorf("csrf の無い段の要求 = %+v, want ヘッダも本文の形も無し", plain)
	}
}

func TestSession_SendsHeaders(t *testing.T) {
	var got http.Header
	srv, _ := recordingServer(t, func(_ http.ResponseWriter, r *http.Request) { got = r.Header.Clone() })
	step := get("h", "/h")
	step.Request.Headers = map[string]string{"Accept-Language": "ja", "X-Test": "1"}
	if _, err := NewSession().Send(t.Context(), srv.Client(), srv.URL, step); err != nil {
		t.Fatal(err)
	}
	if got.Get("Accept-Language") != "ja" || got.Get("X-Test") != "1" {
		t.Errorf("ヘッダ = %v", got)
	}
}

func TestSession_CapturesValuesIntoPath(t *testing.T) {
	srv, reqs := recordingServer(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/create" {
			_, _ = w.Write([]byte(`{"id":"r-1","items":[{"n":7}],"ok":true,"obj":{"a":1},"many":[1,2]}`))
		}
	})
	s := NewSession()
	create := get("create", "/create")
	create.Capture = map[string]string{"id": "$.id", "n": "$.items[0].n", "ok": "$.ok"}
	if _, err := s.Send(t.Context(), srv.Client(), srv.URL, create); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Send(t.Context(), srv.Client(), srv.URL, get("use", "/r/{id}/{n}/{ok}")); err != nil {
		t.Fatal(err)
	}
	if got := reqs()[1].Path; got != "/r/r-1/7/true" {
		t.Errorf("差し込んだパス = %q, want /r/r-1/7/true", got)
	}

	if _, err := s.Send(t.Context(), srv.Client(), srv.URL, get("missing", "/r/{nothing}")); err == nil || !strings.Contains(err.Error(), "nothing") {
		t.Errorf("取り出していない名前の誤り = %v", err)
	}
	if n := len(reqs()); n != 2 {
		t.Errorf("差し込めないパスで要求を送りました: %d 件", n)
	}
	for path, want := range map[string]string{"$.obj": "文字か数か真偽", "$.many[*]": "2 個", "$.none": "0 個", "id": "$ で始め"} {
		bad := get("bad", "/create")
		bad.Capture = map[string]string{"x": path}
		resp, err := s.Send(t.Context(), srv.Client(), srv.URL, bad)
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("capture %s の誤り = %v, want %q を含む", path, err, want)
		}
		if resp.Status != http.StatusOK {
			t.Errorf("capture %s で失敗しても応答を返します: %d", path, resp.Status)
		}
	}
	notJSON := get("text", "/text")
	notJSON.Capture = map[string]string{"x": "$.a"}
	if _, err := s.Send(t.Context(), srv.Client(), srv.URL, notJSON); err == nil || !strings.Contains(err.Error(), "JSON") {
		t.Errorf("JSON でない本文の capture の誤り = %v", err)
	}
}

func TestSession_SendFailures(t *testing.T) {
	s := NewSession()
	bad := Step{Name: "bad", Request: Request{Method: "BAD METHOD", Path: "/"}}
	if _, err := s.Send(t.Context(), http.DefaultClient, "http://127.0.0.1:1", bad); err == nil {
		t.Error("作れない要求を送れました")
	}
	if _, err := s.Send(t.Context(), http.DefaultClient, "http://127.0.0.1:1", get("down", "/")); err == nil {
		t.Error("届かない宛先に送れました")
	}
	unmarshalable := Step{Name: "json", Request: Request{Method: http.MethodPost, Path: "/", JSON: func() {}}}
	if _, err := s.Send(t.Context(), http.DefaultClient, "http://127.0.0.1:1", unmarshalable); err == nil || !strings.Contains(err.Error(), "JSON") {
		t.Errorf("JSON にできない本文の誤り = %v", err)
	}
}

func TestSession_ForgetsCookieExpiredByClock(t *testing.T) {
	s := NewSession()
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	s.now = func() time.Time { return now }
	s.storeCookies([]*http.Cookie{{Name: "a", Value: "1", Path: "/", Secure: true, HttpOnly: true, SameSite: http.SameSiteStrictMode}, {Name: "rel", Value: "2", Path: "x", Secure: true, HttpOnly: true, SameSite: http.SameSiteStrictMode}})
	if _, ok := s.cookie("rel", "/any"); !ok {
		t.Error("/ で始まらないパスの Cookie を / のものとして覚えていません")
	}
	s.storeCookies([]*http.Cookie{{Name: "a", Value: "", Path: "/", Secure: true, HttpOnly: true, SameSite: http.SameSiteStrictMode, Expires: now}})
	if _, ok := s.cookie("a", "/"); ok {
		t.Error("期限が今の Cookie を消していません")
	}
	s.storeCookies([]*http.Cookie{{Name: "a", Value: "3", Path: "/", Secure: true, HttpOnly: true, SameSite: http.SameSiteStrictMode, Expires: now.Add(time.Hour)}})
	if v, ok := s.cookie("a", "/"); !ok || v != "3" {
		t.Errorf("期限の来ていない Cookie = %q %v, want 3", v, ok)
	}
}

func TestPathMatches(t *testing.T) {
	for _, tc := range []struct {
		cookie, request string
		want            bool
	}{
		{"/", "/", true},
		{"/", "", true},
		{"/", "/a", true},
		{"/api", "/api", true},
		{"/api", "/api/x", true},
		{"/api", "/apix", false},
		{"/api/", "/api/x", true},
		{"/api", "/", false},
		{"/api/x", "/api", false},
	} {
		if got := pathMatches(tc.cookie, tc.request); got != tc.want {
			t.Errorf("pathMatches(%q, %q) = %v, want %v", tc.cookie, tc.request, got, tc.want)
		}
	}
}

func TestCheckExpect(t *testing.T) {
	step := Step{Expect: Expect{Status: http.StatusOK, Fields: []string{"$.id", "$.items[*].name"}}}
	ok := Response{Status: http.StatusOK, Body: []byte(`{"id":"1","items":[{"name":"a"}]}`)}
	if p := CheckExpect(step, ok); len(p) != 0 {
		t.Errorf("期待に合う応答の食い違い = %v", p)
	}
	wrong := Response{Status: http.StatusInternalServerError, Body: []byte(`{"items":[]}`)}
	p := CheckExpect(step, wrong)
	if len(p) != 3 || !strings.Contains(p[0], "500") || !strings.Contains(p[0], "200") ||
		!strings.Contains(p[1], "$.id") || !strings.Contains(p[2], "$.items[*].name") {
		t.Errorf("期待に合わない応答の食い違い = %v", p)
	}
	if p := CheckExpect(step, Response{Status: http.StatusOK, Body: []byte("<html>")}); len(p) != 1 || !strings.Contains(p[0], "JSON") {
		t.Errorf("JSON でない本文の食い違い = %v", p)
	}
	if p := CheckExpect(Step{Expect: Expect{Fields: []string{"id"}}}, ok); len(p) != 1 || !strings.Contains(p[0], "$") {
		t.Errorf("$ で始まらない場所の食い違い = %v", p)
	}
	if p := CheckExpect(Step{}, wrong); len(p) != 0 {
		t.Errorf("expect の無い段の食い違い = %v", p)
	}
}

func crossScenario(tos ...string) Scenario {
	s := Scenario{Name: "s", Modes: []string{ModeCross}}
	for i, to := range tos {
		step := get("s"+string(rune('1'+i)), "/")
		step.To = to
		s.Steps = append(s.Steps, step)
	}
	return s
}

func TestRoute_Directions(t *testing.T) {
	j, g := VersionJava, VersionGo
	for _, tc := range []struct {
		name      string
		tos       []string
		direction string
		want      []string
	}{
		{"Java から Go へ", []string{"", ToOther, ToSame, ""}, CrossJavaToGo, []string{j, g, g, j}},
		{"Go から Java へ", []string{"", ToOther, ToSame, ""}, CrossGoToJava, []string{g, j, j, g}},
		{"交互", []string{"", ToOther, ToSame, ""}, CrossAlternate, []string{j, g, j, g}},
		{"最後の段はその前と違う版", []string{"", "", ToOther}, CrossJavaToGo, []string{j, j, g}},
		{"交互の最後の段", []string{"", "", ""}, CrossAlternate, []string{j, g, j}},
		{"2段", []string{"", ""}, CrossGoToJava, []string{g, j}},
	} {
		got, err := CrossRoute(crossScenario(tc.tos...), tc.direction)
		if err != nil || !slices.Equal(got, tc.want) {
			t.Errorf("%s: CrossRoute = %v, %v, want %v", tc.name, got, err, tc.want)
		}
	}
	if _, err := CrossRoute(crossScenario(""), CrossJavaToGo); err == nil || !strings.Contains(err.Error(), "2つ以上") {
		t.Errorf("1段の筋書きの誤り = %v", err)
	}
	if _, err := CrossRoute(crossScenario("", ""), "sideways"); err == nil || !strings.Contains(err.Error(), "sideways") {
		t.Errorf("決めていない送り先の組の誤り = %v", err)
	}
}

func TestRunCross_FailsWhenURLMissingOrRouteInvalid(t *testing.T) {
	f := RunCross(t.Context(), http.DefaultClient, crossScenario("", ""), CrossJavaToGo, map[string]string{})
	if f == nil || f.Step.Index != 1 || f.Version != VersionJava || !strings.Contains(strings.Join(f.Problems, ""), "URL") {
		t.Errorf("URL の無い版の失敗 = %+v", f)
	}
	f = RunCross(t.Context(), http.DefaultClient, crossScenario(""), CrossJavaToGo, map[string]string{})
	if f == nil || f.Step.Index != 0 || f.Direction != CrossJavaToGo {
		t.Errorf("1段の筋書きの失敗 = %+v", f)
	}
	f = RunCross(t.Context(), http.DefaultClient, crossScenario("", ""), CrossJavaToGo,
		map[string]string{VersionJava: "http://127.0.0.1:1", VersionGo: "http://127.0.0.1:1"})
	if f == nil || f.Step.Index != 1 || len(f.Problems) != 1 || !strings.Contains(f.Problems[0], "送れません") {
		t.Errorf("届かない版の失敗 = %+v", f)
	}
}

func TestCrossReport_StringAndWrite(t *testing.T) {
	pass := CrossReport{Scenario: "a/b", Directions: CrossDirections}
	if pass.Failed() || !strings.Contains(pass.String(), "0 件") {
		t.Errorf("失敗の無い報告 = %v %q", pass.Failed(), pass.String())
	}
	fail := CrossReport{Scenario: "a/b", Directions: CrossDirections, Failures: []CrossFailure{
		{Direction: CrossGoToJava, Step: StepRef{Index: 2, Name: "save"}, Version: VersionJava, Problems: []string{"ステータスが 500 でした", "応答の本文: 行1\n行2"}},
		{Direction: CrossAlternate, Problems: []string{"準備の誤り"}},
	}}
	text := fail.String()
	for _, want := range []string{"2 件", "送り先の組: go-to-java / 段: 2「save」 / 送った版: java", "ステータスが 500 でした", "行1\n        行2", "送り先の組: alternate / 段: 段に進む前の準備\n", "準備の誤り"} {
		if !strings.Contains(text, want) {
			t.Errorf("報告に %q がありません:\n%s", want, text)
		}
	}
	if !fail.Failed() {
		t.Error("失敗のある報告が Failed を返しません")
	}
	dir := t.TempDir()
	file, err := fail.Write(dir)
	if err != nil || filepath.Base(file) != "cross-a_b.txt" {
		t.Fatalf("Write = %q, %v", file, err)
	}
	written, err := os.ReadFile(filepath.Clean(file))
	if err != nil || string(written) != text {
		t.Errorf("書いた報告 = %q, %v", written, err)
	}
	if file, err := (CrossReport{Scenario: ".."}).Write(dir); err != nil || filepath.Base(file) != "cross-scenario.txt" {
		t.Errorf("名前が . だけの筋書きの報告 = %q, %v", file, err)
	}
	blocker := filepath.Join(dir, "file")
	if err := os.WriteFile(blocker, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := fail.Write(filepath.Join(blocker, "sub")); err == nil {
		t.Error("作れないフォルダに報告を書けました")
	}
}

func TestRunCross_WritesShortTextBodyAndHashesOthers(t *testing.T) {
	for name, tc := range map[string]struct {
		body []byte
		want string
	}{
		"短い文字":  {[]byte(`{"message":"だめです"}`), `応答の本文: {"message":"だめです"}`},
		"長い文字":  {[]byte(strings.Repeat("a", 2001)), "応答の本文: 2001 バイト sha256:"},
		"文字でない": {[]byte{0xff, 0xfe}, "応答の本文: 2 バイト sha256:"},
	} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write(tc.body)
		}))
		s := crossScenario("", "")
		s.Steps[0].Expect.Status = http.StatusOK
		f := RunCross(t.Context(), srv.Client(), s, CrossJavaToGo, map[string]string{VersionJava: srv.URL, VersionGo: srv.URL})
		srv.Close()
		if f == nil || len(f.Problems) != 2 || !strings.Contains(f.Problems[0], "400") || !strings.HasPrefix(f.Problems[1], tc.want) {
			t.Errorf("%s: 失敗 = %+v, want ステータスの食い違いと %q", name, f, tc.want)
		}
	}
}
