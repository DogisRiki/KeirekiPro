//go:build compat

package harness

import (
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync"
	"testing"
)

// sentRequest は、記録する送り方が受けた1つの要求の、宛先の URL と Host である。
type sentRequest struct{ url, host string }

// recordingTransport は、要求を送らずに宛先の URL と Host を記録し、200 で答える送り方である。
type recordingTransport struct {
	mu   sync.Mutex
	sent []sentRequest
}

func (rt *recordingTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	rt.mu.Lock()
	rt.sent = append(rt.sent, sentRequest{url: r.URL.String(), host: r.Host})
	rt.mu.Unlock()
	return &http.Response{StatusCode: http.StatusOK, Header: http.Header{}, Body: io.NopCloser(strings.NewReader("")), Request: r}, nil
}

func (rt *recordingTransport) requests() []sentRequest {
	rt.mu.Lock()
	defer rt.mu.Unlock()
	return slices.Clone(rt.sent)
}

func TestAbsoluteURL_FakeAWSRewrite(t *testing.T) {
	const signed = "/keirekipro-storage//u-1/a.png?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Expires=600&X-Amz-Signature=abc"
	targets := func(endpoint string) AbsoluteTargets {
		return AbsoluteTargets{OIDCURL: "http://127.0.0.1:18080", AWSURL: "http://127.0.0.1:14566", AWSEndpoint: endpoint}
	}
	for _, tc := range []struct {
		name     string
		url      string
		endpoint string
		want     sentRequest
	}{
		// 版が返す署名付きの URL は、宛先をテストの処理から届く偽の AWS にし、Host を版の AWS の接続先にする。
		// パスの // と問い合わせは、そのまま送る
		{"Java 版の画像", "http://localhost:4566" + signed, "http://fakeaws-java:4566", sentRequest{"http://127.0.0.1:14566" + signed, "fakeaws-java:4566"}},
		{"Go 版の画像", "http://localhost:4566" + signed, "http://fakeaws-go:4566", sentRequest{"http://127.0.0.1:14566" + signed, "fakeaws-go:4566"}},
		{"取り出した URL", "{imageURL}", "http://fakeaws-go:4566", sentRequest{"http://127.0.0.1:14566/b/k.png?X-Amz-Signature=s", "fakeaws-go:4566"}},
		// localhost:4566 のほかのホストの URL は書き換えない
		{"ほかのポート", "http://localhost:4567/b/k", "http://fakeaws-go:4566", sentRequest{"http://localhost:4567/b/k", "localhost:4567"}},
		{"ポートの無い localhost", "http://localhost/b/k", "http://fakeaws-go:4566", sentRequest{"http://localhost/b/k", "localhost"}},
		{"ほかのホストのポート 4566", "http://127.0.0.1:4566/b/k", "http://fakeaws-go:4566", sentRequest{"http://127.0.0.1:4566/b/k", "127.0.0.1:4566"}},
		{"版の AWS の接続先の名前", "http://fakeaws-go:4566/b/k", "http://fakeaws-go:4566", sentRequest{"http://fakeaws-go:4566/b/k", "fakeaws-go:4566"}},
		{"fakeoidc", "http://fakeoidc:8080/o/auth?x=1", "http://fakeaws-go:4566", sentRequest{"http://127.0.0.1:18080/o/auth?x=1", "127.0.0.1:18080"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			rt := &recordingTransport{}
			s := NewSession()
			s.vars["imageURL"] = "http://localhost:4566/b/k.png?X-Amz-Signature=s"
			step := Step{Name: "read-image", Request: Request{Method: http.MethodGet, URL: tc.url}}
			if _, err := s.SendAbsolute(t.Context(), &http.Client{Transport: rt}, targets(tc.endpoint), step); err != nil {
				t.Fatal(err)
			}
			if got := rt.requests(); !slices.Equal(got, []sentRequest{tc.want}) {
				t.Errorf("送った要求 = %+v, want %+v", got, tc.want)
			}
		})
	}

	// 偽の AWS のアドレスか版の AWS の接続先が無いときは、localhost:4566 に送らずに段の誤りにする
	for name, tg := range map[string]AbsoluteTargets{
		"偽の AWS のアドレスが無い":     {AWSEndpoint: "http://fakeaws-go:4566"},
		"版の AWS の接続先が無い":      {AWSURL: "http://127.0.0.1:14566"},
		"偽の AWS のアドレスを読めない":   {AWSURL: "://bad", AWSEndpoint: "http://fakeaws-go:4566"},
		"版の AWS の接続先を読めない":    {AWSURL: "http://127.0.0.1:14566", AWSEndpoint: "://bad"},
		"版の AWS の接続先にホストが無い":  {AWSURL: "http://127.0.0.1:14566", AWSEndpoint: "/path"},
		"偽の AWS のアドレスにホストが無い": {AWSURL: "/path", AWSEndpoint: "http://fakeaws-go:4566"},
	} {
		rt := &recordingTransport{}
		step := Step{Name: "bad", Request: Request{Method: http.MethodGet, URL: "http://localhost:4566/b/k"}}
		_, err := NewSession().SendAbsolute(t.Context(), &http.Client{Transport: rt}, tg, step)
		if err == nil || !strings.Contains(err.Error(), "段 bad ") {
			t.Errorf("%s: 誤り = %v, want 段 bad の誤り", name, err)
		}
		if got := rt.requests(); len(got) != 0 {
			t.Errorf("%s: 要求を送りました: %+v", name, got)
		}
	}
}

func TestExpectValues_WithCapturedNames(t *testing.T) {
	s := NewSession()
	s.vars["newName"] = "新しい名前"
	s.vars["mail"] = "a@example.com"
	body := []byte(`{"username":"新しい名前","email":"a@example.com","twoFactorAuthEnabled":true,"count":2,` +
		`"profileImage":null,"roles":["USER","ADMIN"],"user":{"name":"<b>"}}`)
	resp := Response{Status: http.StatusOK, Body: body}
	// 取り出した名前を差し込んだ値と、真偽と数と null と並びと入れ子の値が合えば、合わないことは無い
	ok := Step{Name: "read", Expect: Expect{Values: map[string]any{
		"$.username":             "{newName}",
		"$.email":                "{mail}",
		"$.twoFactorAuthEnabled": true,
		"$.count":                2,
		"$.profileImage":         nil,
		"$.roles":                []any{"USER", "ADMIN"},
		"$.roles[1]":             "ADMIN",
		"$.user":                 map[string]any{"name": "<b>"},
	}}}
	if got := s.CheckValues(ok, resp); len(got) != 0 {
		t.Errorf("合う値の段の報告 = %q, want 無し", got)
	}
	if ok.Expect.Values["$.username"] != "{newName}" {
		t.Errorf("筋書きの段が書き換わりました: %v", ok.Expect.Values)
	}

	// 合わないときは、段の名前と、場所と、期待した値と、受けた値を書く
	bad := Step{Name: "check-name", Expect: Expect{Values: map[string]any{
		"$.username":     "{mail}",
		"$.count":        "2",
		"$.roles":        []any{"ADMIN", "USER"},
		"$.none":         "x",
		"$.roles[*]":     "USER",
		"$.profileImage": "",
	}}}
	want := []string{
		`段 check-name の $.count の値が 2 でした。期待は "2" です`,
		`段 check-name の $.none の値が (無し) でした。期待は "x" です`,
		`段 check-name の $.profileImage の値が null でした。期待は "" です`,
		`段 check-name の $.roles の値が ["USER","ADMIN"] でした。期待は ["ADMIN","USER"] です`,
		`段 check-name の $.roles[*] の値が 2 個の値 ["USER","ADMIN"] でした。期待は "USER" です`,
		`段 check-name の $.username の値が "新しい名前" でした。期待は "a@example.com" です`,
	}
	if got := s.CheckValues(bad, resp); !slices.Equal(got, want) {
		t.Errorf("合わない値の段の報告 =\n%s\nwant\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}

	// 取り出していない名前は段の誤りにし、JSON でない本文は確かめられないと書く
	missing := Step{Name: "bad", Expect: Expect{Values: map[string]any{"$.username": "{other}"}}}
	if got := s.CheckValues(missing, resp); len(got) != 1 || !strings.Contains(got[0], "段 bad ") || !strings.Contains(got[0], "other") {
		t.Errorf("取り出していない名前の報告 = %q", got)
	}
	if got := s.CheckValues(ok, Response{Status: http.StatusOK, Body: []byte("not json")}); len(got) != 1 ||
		!strings.HasPrefix(got[0], "段 read の expect の values を確かめられません。本文を JSON として読めません") {
		t.Errorf("JSON でない本文の報告 = %q", got)
	}
	// expect.values の無い段は、本文を読まない
	if got := s.CheckValues(Step{Name: "none"}, Response{Body: []byte("not json")}); len(got) != 0 {
		t.Errorf("values の無い段の報告 = %q", got)
	}
}

// imageServer は、パスごとに決めた Content-Type と本文で答えるサーバである。Content-Type を空にしたパスは、Content-Type を送らない。
func imageServer(t *testing.T, files map[string][2]string) string {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f, ok := files[r.URL.Path]
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.Header()["Content-Type"] = nil
		if f[0] != "" {
			w.Header().Set("Content-Type", f[0])
		}
		_, _ = w.Write([]byte(f[1]))
	}))
	t.Cleanup(srv.Close)
	return srv.URL
}

func TestExpectBodyFile_SizeAndSHA256Only(t *testing.T) {
	png, gif := imageFixture(t, "profile.png"), imageFixture(t, "profile.gif")
	base := imageServer(t, map[string][2]string{"/png": {"image/png", string(png)}, "/gif": {"image/gif", string(gif)}})
	step := func(path, file string) Step {
		return Step{Name: "read-image", Request: Request{Method: http.MethodGet, URL: base + path}, Expect: Expect{Status: http.StatusOK, BodyFile: file}}
	}
	if _, err := NewSession().SendAbsolute(t.Context(), http.DefaultClient, AbsoluteTargets{}, step("/png", "profile.png")); err != nil {
		t.Errorf("同じ画像の段の誤り = %v", err)
	}

	// 違う画像は、段の名前と、受けた本文と期待したファイルの大きさと SHA-256 だけを書き、中身を書かない
	_, err := NewSession().SendAbsolute(t.Context(), http.DefaultClient, AbsoluteTargets{}, step("/gif", "profile.png"))
	want := "harness: 段 read-image の応答の本文が " + describeBytes(gif) + " でした。期待は fixtures/images/profile.png の " + describeBytes(png) + " です"
	if err == nil || err.Error() != want {
		t.Fatalf("違う画像の段の誤り = %v, want %s", err, want)
	}
	for _, raw := range []string{"PNG", "GIF8"} {
		if strings.Contains(err.Error(), raw) {
			t.Errorf("誤りに画像の中身 %q が入っています", raw)
		}
	}

	// 無いファイルは、読めないことを段の誤りにする
	_, err = NewSession().SendAbsolute(t.Context(), http.DefaultClient, AbsoluteTargets{}, step("/png", "none.png"))
	if err == nil || !strings.Contains(err.Error(), `段 read-image の expect の body_file "none.png" を読めません`) {
		t.Errorf("無いファイルの段の誤り = %v", err)
	}

	// ステータスと画像の両方が外れたときは、両方を書く
	_, err = NewSession().SendAbsolute(t.Context(), http.DefaultClient, AbsoluteTargets{}, step("/none", "profile.png"))
	if err == nil || !strings.Contains(err.Error(), "段 read-image のステータスが 404 でした。期待は 200 です") ||
		!strings.Contains(err.Error(), "段 read-image の応答の本文が "+describeBytes([]byte{})+" でした") {
		t.Errorf("ステータスと画像が外れた段の誤り = %v", err)
	}
}

func TestExpectContentType(t *testing.T) {
	base := imageServer(t, map[string][2]string{"/png": {"image/png", "x"}, "/charset": {"image/png;charset=UTF-8", "x"}, "/none": {"", "x"}})
	send := func(path, want string) error {
		step := Step{Name: "read-image", Request: Request{Method: http.MethodGet, URL: base + path}, Expect: Expect{ContentType: want}}
		_, err := NewSession().SendAbsolute(t.Context(), http.DefaultClient, AbsoluteTargets{}, step)
		return err
	}
	if err := send("/png", "image/png"); err != nil {
		t.Errorf("同じ Content-Type の段の誤り = %v", err)
	}
	// Content-Type は文字の並びのまま比べ、外れたときは期待した値と受けた値を書く
	for path, want := range map[string]string{
		"/charset": `harness: 段 read-image の応答の Content-Type が "image/png;charset=UTF-8" でした。期待は "image/png" です`,
		"/none":    `harness: 段 read-image の応答の Content-Type が "" でした。期待は "image/png" です`,
	} {
		if err := send(path, "image/png"); err == nil || err.Error() != want {
			t.Errorf("%s の段の誤り = %v, want %s", path, err, want)
		}
	}
	// content_type の無い段は、Content-Type を確かめない
	if err := send("/charset", ""); err != nil {
		t.Errorf("content_type の無い段の誤り = %v", err)
	}
}
