//go:build compat

package harness

import (
	"io"
	"net/http"
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
