//go:build compat

package harness

import (
	"context"
	"encoding/json"
	"io"
	"maps"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
)

// fakeMailbox は、偽の AWS が覚えたメールの代わりである。サーバの処理がメールを足し、Session が読む。
type fakeMailbox struct {
	mu    sync.Mutex
	mails []fakeaws.Email
	reads int
}

func (m *fakeMailbox) add(text string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.mails = append(m.mails, fakeaws.Email{Subject: "件名", Text: text})
}

func (m *fakeMailbox) read(context.Context) ([]fakeaws.Email, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.reads++
	return append([]fakeaws.Email(nil), m.mails...), nil
}

// sourcesServer は、取り出しの5つの元を試すための応答を返すサーバである。/mail はメールを2通足す。
func sourcesServer(t *testing.T, box *fakeMailbox) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Location", "http://compat.test/api/auth/oidc/callback?code=c-1&state=s%2F1")
		w.Header().Add("X-One", "v1")
		w.Header().Add("X-One", "v2")
		w.Header().Set("X-Bad", "http://[::1")
		w.Header().Add("Set-Cookie", "refreshToken=r-old; Path=/api/auth")
		w.Header().Add("Set-Cookie", "refreshToken=r-1; Path=/api/auth; HttpOnly")
		w.Header().Add("Set-Cookie", "accessToken=a-1; Path=/")
		if r.URL.Path == "/mail" {
			box.add("2段階認証コード: 222222")
			box.add("2段階認証コード: 333333\n2行目 444444")
		}
		_, _ = w.Write([]byte(`{"id":"j-1","n":2}`))
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestCapture_Sources(t *testing.T) {
	box := &fakeMailbox{}
	box.add("前の段のメール: 111111")
	srv := sourcesServer(t, box)
	s := NewSession()
	s.SetMailReader(box.read)
	step := get("all", "/mail")
	step.Capture = map[string]string{
		"json":     "$.id",
		"text":     "text",
		"header":   "header:X-One",
		"location": "header:Location",
		"code":     "header:Location?code",
		"state":    "header:location?state",
		"cookie":   "cookie:refreshToken",
		"access":   "cookie:accessToken",
		"mail":     `mail:コード: (\d{6})`,
	}
	if _, err := s.Send(t.Context(), srv.Client(), srv.URL, step); err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"json":     "j-1",
		"text":     `{"id":"j-1","n":2}`,
		"header":   "v1",
		"location": "http://compat.test/api/auth/oidc/callback?code=c-1&state=s%2F1",
		"code":     "c-1",
		"state":    "s/1",
		"cookie":   "r-1",
		"access":   "a-1",
		"mail":     "333333",
	}
	if !reflect.DeepEqual(s.vars, want) {
		t.Errorf("取り出した値 = %v, want %v", s.vars, want)
	}

	// メールを取り出さない段では、メールを読まない
	reads := box.reads
	plain := get("plain", "/plain")
	plain.Capture = map[string]string{"text": "text"}
	if _, err := s.Send(t.Context(), srv.Client(), srv.URL, plain); err != nil {
		t.Fatal(err)
	}
	if box.reads != reads {
		t.Errorf("メールを取り出さない段で、メールを %d 回読みました", box.reads-reads)
	}
	// JSON でない本文でも、JSON の場所を使わなければ取り出せる
	html := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Location", "/x?y=1")
		_, _ = w.Write([]byte("<html>"))
	}))
	t.Cleanup(html.Close)
	h := get("html", "/")
	h.Capture = map[string]string{"y": "header:Location?y", "body": "text"}
	if _, err := s.Send(t.Context(), html.Client(), html.URL, h); err != nil {
		t.Fatal(err)
	}
	if s.vars["y"] != "1" || s.vars["body"] != "<html>" {
		t.Errorf("JSON でない本文の段で取り出した値 = %q %q", s.vars["y"], s.vars["body"])
	}
	// 写しの Session も、同じメールの読み方を使う
	again := get("again", "/mail")
	again.Capture = map[string]string{"again": `mail:コード: (\d{6})`}
	c := s.Clone()
	if _, err := c.Send(t.Context(), srv.Client(), srv.URL, again); err != nil {
		t.Fatal(err)
	}
	if c.vars["again"] != "333333" {
		t.Errorf("写しの Session で取り出した値 = %q, want 333333", c.vars["again"])
	}
}

func TestCapture_MissingFailsWithNames(t *testing.T) {
	// 段の前に届いたメールは、その段のあとに届いたメールに数えない
	box := &fakeMailbox{}
	box.add("前の段のメール: 111111")
	srv := sourcesServer(t, box)
	for source, want := range map[string]string{
		"$.none":                "0 個",
		"header:X-None":         "X-None",
		"header:Location?none":  "none",
		"header:X-Bad?x":        "URL",
		"cookie:none":           "none",
		`mail:(\d{6})`:          "メールがありません",
		`mail:コード: (\d{6})x`:    "当たりません",
		"$.id":                  "",
		"body":                  "$ で始め",
		`mail:コード: (\d{6})\n無い`: "当たりません",
	} {
		s := NewSession()
		s.SetMailReader(box.read)
		path := "/plain"
		if strings.HasSuffix(source, "x") || strings.Contains(source, "無い") {
			path = "/mail"
		}
		step := get("find", path)
		step.Capture = map[string]string{"x": source}
		resp, err := s.Send(t.Context(), srv.Client(), srv.URL, step)
		if want == "" {
			if err != nil {
				t.Errorf("取り出せる %s の誤り = %v", source, err)
			}
			continue
		}
		if err == nil || !strings.Contains(err.Error(), "段 find") || !strings.Contains(err.Error(), "capture x") || !strings.Contains(err.Error(), want) {
			t.Errorf("取り出しの元 %s の誤り = %v, want 段 find と capture x と %q を含む", source, err, want)
		}
		if resp.Status != http.StatusOK {
			t.Errorf("取り出しの元 %s で失敗しても応答を返します: %d", source, resp.Status)
		}
	}

	// メールを読む部品が無いときは、要求を送らずに失敗する
	var sent atomic.Int32
	counting := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { sent.Add(1) }))
	t.Cleanup(counting.Close)
	step := get("find", "/")
	step.Capture = map[string]string{"x": `mail:(\d+)`}
	if _, err := NewSession().Send(t.Context(), counting.Client(), counting.URL, step); err == nil || !strings.Contains(err.Error(), "段 find") || !strings.Contains(err.Error(), "メールを読む") {
		t.Errorf("メールを読む部品が無い段の誤り = %v", err)
	}
	if n := sent.Load(); n != 0 {
		t.Errorf("メールを読む部品が無い段で %d 件の要求を送りました", n)
	}
}

func TestCapture_ScenarioRejectsBadSources(t *testing.T) {
	ok := []string{`"$.x"`, `"text"`, `"header:Location"`, `"header:Location?code"`, `"cookie:refreshToken"`, `"mail:(\\d{6})"`}
	for _, source := range ok {
		steps := "  - name: s\n    request: {method: GET, path: /x}\n    capture: {x: " + source + "}\n"
		if _, err := LoadScenario(writeScenario(t, kindsScenario("compare", steps))); err != nil {
			t.Errorf("取り出しの元 %s を断りました: %v", source, err)
		}
	}
	for source, want := range map[string]string{
		`"token"`:              `"token"`,
		`"$x"`:                 "$",
		`"header:"`:            "ヘッダの名前",
		`"header:?code"`:       "ヘッダの名前",
		`"header:Location?"`:   "問い合わせの項目",
		`"cookie:"`:            "Cookie の名前",
		`"mail:("`:             "正規表現",
		`"mail:\\d{6}"`:        "組",
		`"text:"`:              "$ で始め",
		`"mail:"`:              "組",
		`"header:Location?a?"`: "",
	} {
		steps := "  - name: s\n    request: {method: GET, path: /x}\n    capture: {x: " + source + "}\n"
		_, err := LoadScenario(writeScenario(t, kindsScenario("compare", steps)))
		if want == "" {
			if err != nil {
				t.Errorf("取り出しの元 %s を断りました: %v", source, err)
			}
			continue
		}
		if err == nil || !strings.Contains(err.Error(), "段 s の capture x") || !strings.Contains(err.Error(), want) {
			t.Errorf("取り出しの元 %s の誤り = %v, want %q を含む", source, err, want)
		}
	}
}

func TestSubstitute_BodyHeaderAndCookie(t *testing.T) {
	type got struct {
		path, test, cookie string
		body               map[string]any
	}
	var mu sync.Mutex
	var reqs []got
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		var body map[string]any
		_ = json.Unmarshal(b, &body)
		mu.Lock()
		reqs = append(reqs, got{path: r.URL.Path, test: r.Header.Get("X-Test"), cookie: r.Header.Get("Cookie"), body: body})
		mu.Unlock()
		if r.URL.Path == "/login" {
			w.Header().Add("Set-Cookie", "refreshToken=r-1; Path=/")
			_, _ = w.Write([]byte(`{"id":"u-1","name":"n-1"}`))
		}
	}))
	t.Cleanup(srv.Close)
	s := NewSession()
	login := get("login", "/login")
	login.Capture = map[string]string{"id": "$.id", "name": "$.name", "old": "cookie:refreshToken"}
	if _, err := s.Send(t.Context(), srv.Client(), srv.URL, login); err != nil {
		t.Fatal(err)
	}
	s.storeCookies([]*http.Cookie{{Name: "refreshToken", Value: "r-2", Path: "/", Secure: true, HttpOnly: true, SameSite: http.SameSiteStrictMode}})

	body := map[string]any{"a": "x-{id}-{name}", "nested": map[string]any{"list": []any{"{name}", 1, true, nil}}, "k": 5, "{id}": "key"}
	use := Step{Name: "use", Request: Request{
		Method: http.MethodPost, Path: "/p/{id}", JSON: body,
		Headers: map[string]string{"X-Test": "h-{id}", "Cookie": "refreshToken={old}"},
	}}
	if _, err := s.Send(t.Context(), srv.Client(), srv.URL, use); err != nil {
		t.Fatal(err)
	}
	recordedReqs := func() []got {
		mu.Lock()
		defer mu.Unlock()
		return append([]got(nil), reqs...)
	}
	last := recordedReqs()[len(recordedReqs())-1]
	wantBody := map[string]any{"a": "x-u-1-n-1", "nested": map[string]any{"list": []any{"n-1", 1.0, true, nil}}, "k": 5.0, "{id}": "key"}
	if last.path != "/p/u-1" || last.test != "h-u-1" || !reflect.DeepEqual(last.body, wantBody) {
		t.Errorf("差し込んだ要求 = %+v, want 経路 /p/u-1、ヘッダ h-u-1、本文 %v", last, wantBody)
	}
	// 筋書きに書いた Cookie ヘッダの値を先に置き、Cookie の束の値を後ろに続ける
	if last.cookie != "refreshToken=r-1; refreshToken=r-2" {
		t.Errorf("Cookie ヘッダ = %q, want 取り出した古い値と、束の今の値", last.cookie)
	}
	// 差し込みは、筋書きの段の本文を書き換えない。Java 版と Go 版で同じ段を使うためである
	if !reflect.DeepEqual(use.Request.JSON, map[string]any{"a": "x-{id}-{name}", "nested": map[string]any{"list": []any{"{name}", 1, true, nil}}, "k": 5, "{id}": "key"}) {
		t.Errorf("段の本文が書き換わりました: %v", use.Request.JSON)
	}

	sent := len(recordedReqs())
	for name, step := range map[string]Step{
		"本文":     {Name: "b", Request: Request{Method: http.MethodPost, Path: "/x", JSON: map[string]any{"list": []any{"{nothing1}"}}}},
		"ヘッダ":    {Name: "h", Request: Request{Method: http.MethodGet, Path: "/x", Headers: map[string]string{"X-Test": "{nothing2}"}}},
		"Cookie": {Name: "c", Request: Request{Method: http.MethodGet, Path: "/x", Headers: map[string]string{"Cookie": "a={nothing3}"}}},
	} {
		if _, err := s.Send(t.Context(), srv.Client(), srv.URL, step); err == nil || !strings.Contains(err.Error(), "nothing") || !strings.Contains(err.Error(), "段 "+step.Name) {
			t.Errorf("%s の取り出していない名前の誤り = %v", name, err)
		}
	}
	if n := len(recordedReqs()); n != sent {
		t.Errorf("差し込めない段で %d 件の要求を送りました", n-sent)
	}
	if !maps.Equal(s.vars, map[string]string{"id": "u-1", "name": "n-1", "old": "r-1"}) {
		t.Errorf("取り出した値 = %v", s.vars)
	}
}
