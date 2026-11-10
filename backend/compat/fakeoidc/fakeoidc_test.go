//go:build compat

package fakeoidc_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"reflect"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeoidc"
	"github.com/DogisRiki/KeirekiPro/backend/compat/harness"
)

const (
	redirectURI = "http://java:8080/api/auth/oidc/callback"
	verifier    = "fakeoidc-test-verifier-0123456789-abcdefghijklmnop"
)

var (
	googleUser = fakeoidc.GoogleUser{Sub: "google-sub-1", Name: "山田 太郎", Email: "taro@example.com", EmailVerified: true}
	githubUser = fakeoidc.GitHubUser{ID: 12345, Login: "octo-taro", Emails: []fakeoidc.GitHubEmail{
		{Email: "old@example.com", Primary: false, Verified: true},
		{Email: "taro@example.com", Primary: true, Verified: true},
	}}
)

// fixture は、テストの処理の中で動かす fakeoidc と、転送をたどらない HTTP のクライアントである。
type fixture struct {
	t      *testing.T
	base   string
	client *http.Client
}

// newFixture は、両方の提供元のクライアントを比べる検査の口で登録した fixture を作る。
func newFixture(t *testing.T) fixture {
	t.Helper()
	f := newBareFixture(t)
	f.putClient(fakeoidc.Google, testClient(fakeoidc.Google))
	f.putClient(fakeoidc.GitHub, testClient(fakeoidc.GitHub))
	return f
}

// newBareFixture は、クライアントも利用者も登録していない fixture を作る。
func newBareFixture(t *testing.T) fixture {
	t.Helper()
	srv := httptest.NewServer(fakeoidc.NewServer())
	t.Cleanup(srv.Close)
	return fixture{t: t, base: srv.URL, client: noRedirectClient()}
}

// testClient は、テストで登録する提供元 provider のクライアントの値である。
func testClient(provider string) fakeoidc.Client {
	return fakeoidc.Client{ID: "test-" + provider + "-client", Secret: "test-" + provider + "-client-secret", RedirectURIs: []string{"http://go:8080/api/auth/oidc/callback", redirectURI}}
}

func noRedirectClient() *http.Client {
	return &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
}

func challengeOf(v string) string {
	sum := sha256.Sum256([]byte(v))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

// do は、要求を送り、応答のステータスとヘッダと本文を返す。
func (f fixture) do(req *http.Request) (int, http.Header, []byte) {
	f.t.Helper()
	resp, err := f.client.Do(req)
	if err != nil {
		f.t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		f.t.Fatal(err)
	}
	return resp.StatusCode, resp.Header, body
}

func (f fixture) request(method, path string, body io.Reader) *http.Request {
	f.t.Helper()
	req, err := http.NewRequestWithContext(f.t.Context(), method, f.base+path, body)
	if err != nil {
		f.t.Fatal(err)
	}
	return req
}

// putClient は、比べる検査の口で、提供元 provider のクライアントを登録する。
func (f fixture) putClient(provider string, c fakeoidc.Client) {
	f.t.Helper()
	req := f.request(http.MethodPut, "/_compat/clients/"+provider, strings.NewReader(c.Form().Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if status, _, body := f.do(req); status != http.StatusNoContent {
		f.t.Fatalf("%s のクライアントの登録 = %d %s, want 204", provider, status, body)
	}
}

// putUser は、比べる検査の口で、提供元 provider の利用者を登録する。
func (f fixture) putUser(provider string, user any) {
	f.t.Helper()
	data, err := json.Marshal(user)
	if err != nil {
		f.t.Fatal(err)
	}
	if status, _, body := f.do(f.request(http.MethodPut, "/_compat/users/"+provider, bytes.NewReader(data))); status != http.StatusNoContent {
		f.t.Fatalf("%s の利用者の登録 = %d %s, want 204", provider, status, body)
	}
}

// authorize は、認可の口に要求を送り、転送先の URL を返す。
func (f fixture) authorize(path string, params url.Values) *url.URL {
	f.t.Helper()
	status, header, body := f.do(f.request(http.MethodGet, path+"?"+params.Encode(), http.NoBody))
	if status != http.StatusFound {
		f.t.Fatalf("認可の口 %s = %d %s, want 302", path, status, body)
	}
	location, err := url.Parse(header.Get("Location"))
	if err != nil {
		f.t.Fatal(err)
	}
	return location
}

func googleAuthParams(state string) url.Values {
	return url.Values{
		"client_id":             {testClient(fakeoidc.Google).ID},
		"response_type":         {"code"},
		"scope":                 {"openid email profile"},
		"redirect_uri":          {redirectURI},
		"state":                 {state},
		"code_challenge":        {challengeOf(verifier)},
		"code_challenge_method": {"S256"},
	}
}

func githubAuthParams(state string) url.Values {
	params := googleAuthParams(state)
	params.Set("client_id", testClient(fakeoidc.GitHub).ID)
	params.Set("scope", "read:user user:email")
	params.Del("response_type")
	return params
}

// tokenForm は、Java 版と同じく、クライアントの値を本文に入れた token の口の要求の本文である。
func tokenForm(provider, code string) url.Values {
	return url.Values{
		"grant_type":    {"authorization_code"},
		"code":          {code},
		"redirect_uri":  {redirectURI},
		"code_verifier": {verifier},
		"client_id":     {testClient(provider).ID},
		"client_secret": {testClient(provider).Secret},
	}
}

func (f fixture) postToken(path string, form url.Values, accept string) (int, http.Header, []byte) {
	f.t.Helper()
	req := f.request(http.MethodPost, path, strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if accept != "" {
		req.Header.Set("Accept", accept)
	}
	return f.do(req)
}

func (f fixture) getWithToken(path, accessToken string) (int, []byte) {
	f.t.Helper()
	req := f.request(http.MethodGet, path, http.NoBody)
	if accessToken != "" {
		req.Header.Set("Authorization", "Bearer "+accessToken)
	}
	status, _, body := f.do(req)
	return status, body
}

func decode[T any](t *testing.T, body []byte) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(body, &v); err != nil {
		t.Fatalf("本文 %s を読めません: %v", body, err)
	}
	return v
}

// TestGoogleFlow_ReturnsScenarioUser は、Google の認可と token と userinfo の流れで、登録した利用者の値が返ることを確かめる。
func TestGoogleFlow_ReturnsScenarioUser(t *testing.T) {
	f := newFixture(t)
	f.putUser(fakeoidc.Google, googleUser)

	location := f.authorize("/o/oauth2/v2/auth", googleAuthParams("state-g1"))
	code := location.Query().Get("code")
	if location.Scheme+"://"+location.Host+location.Path != redirectURI || code == "" || location.Query().Get("state") != "state-g1" {
		t.Fatalf("転送先 = %s, want %s?code=...&state=state-g1", location, redirectURI)
	}

	status, _, body := f.postToken("/token", tokenForm(fakeoidc.Google, code), "application/json")
	token := decode[map[string]any](t, body)
	accessToken, _ := token["access_token"].(string)
	if status != http.StatusOK || accessToken == "" || token["token_type"] != "Bearer" {
		t.Fatalf("token の口 = %d %s, want 200 と Bearer のアクセストークン", status, body)
	}

	// 認可のコードは1回しか使えない
	if status, _, body := f.postToken("/token", tokenForm(fakeoidc.Google, code), ""); status != http.StatusBadRequest ||
		decode[map[string]string](t, body)["error"] != "invalid_grant" {
		t.Errorf("使い済みのコードの token の口 = %d %s, want 400 invalid_grant", status, body)
	}

	status, body = f.getWithToken("/v1/userinfo", accessToken)
	if got := decode[fakeoidc.GoogleUser](t, body); status != http.StatusOK || got != googleUser {
		t.Errorf("userinfo = %d %+v, want 200 %+v", status, got, googleUser)
	}
	if status, _ := f.getWithToken("/v1/userinfo", ""); status != http.StatusUnauthorized {
		t.Errorf("アクセストークンの無い userinfo = %d, want 401", status)
	}
}

// TestGoogleToken_ChecksClientRedirectAndVerifier は、token の口が、クライアントの値と redirect_uri と PKCE の
// code_verifier を確かめ、Go の oauth2 の形の Basic 認証でもクライアントの値を受けることを確かめる。
func TestGoogleToken_ChecksClientRedirectAndVerifier(t *testing.T) {
	f := newFixture(t)
	f.putUser(fakeoidc.Google, googleUser)
	newCode := func() string {
		return f.authorize("/o/oauth2/v2/auth", googleAuthParams("s")).Query().Get("code")
	}

	tests := []struct {
		name       string
		change     func(url.Values)
		wantStatus int
		wantError  string
	}{
		{"クライアントの秘密の値が違う", func(v url.Values) { v.Set("client_secret", "wrong") }, http.StatusUnauthorized, "invalid_client"},
		{"redirect_uri が違う", func(v url.Values) { v.Set("redirect_uri", "http://go:8080/other") }, http.StatusBadRequest, "invalid_grant"},
		{"code_verifier が違う", func(v url.Values) { v.Set("code_verifier", "wrong-verifier") }, http.StatusBadRequest, "invalid_grant"},
		{"code_verifier が無い", func(v url.Values) { v.Del("code_verifier") }, http.StatusBadRequest, "invalid_grant"},
		{"grant_type が違う", func(v url.Values) { v.Set("grant_type", "refresh_token") }, http.StatusBadRequest, "unsupported_grant_type"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			form := tokenForm(fakeoidc.Google, newCode())
			tc.change(form)
			status, _, body := f.postToken("/token", form, "")
			if got := decode[map[string]string](t, body)["error"]; status != tc.wantStatus || got != tc.wantError {
				t.Errorf("token の口 = %d %s, want %d %s", status, body, tc.wantStatus, tc.wantError)
			}
		})
	}

	t.Run("Basic 認証のクライアントの値を受ける", func(t *testing.T) {
		form := tokenForm(fakeoidc.Google, newCode())
		form.Del("client_id")
		form.Del("client_secret")
		req := f.request(http.MethodPost, "/token", strings.NewReader(form.Encode()))
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		client := testClient(fakeoidc.Google)
		req.SetBasicAuth(url.QueryEscape(client.ID), url.QueryEscape(client.Secret))
		if status, _, body := f.do(req); status != http.StatusOK {
			t.Errorf("Basic 認証の token の口 = %d %s, want 200", status, body)
		}
	})
}

// TestGitHubFlow_ReturnsScenarioUserAndEmails は、GitHub の認可と access_token と /user と /user/emails の流れで、
// 登録した利用者の値とメールアドレスが返ることを確かめる。
func TestGitHubFlow_ReturnsScenarioUserAndEmails(t *testing.T) {
	f := newFixture(t)
	f.putUser(fakeoidc.GitHub, githubUser)

	location := f.authorize("/login/oauth/authorize", githubAuthParams("state-h1"))
	code := location.Query().Get("code")
	if location.Scheme+"://"+location.Host+location.Path != redirectURI || code == "" || location.Query().Get("state") != "state-h1" {
		t.Fatalf("転送先 = %s, want %s?code=...&state=state-h1", location, redirectURI)
	}
	status, _, body := f.postToken("/login/oauth/access_token", tokenForm(fakeoidc.GitHub, code), "application/json")
	token := decode[map[string]string](t, body)
	if status != http.StatusOK || token["access_token"] == "" || token["token_type"] != "bearer" {
		t.Fatalf("access_token の口 = %d %s, want 200 と bearer のアクセストークン", status, body)
	}

	status, body = f.getWithToken("/user", token["access_token"])
	user := decode[map[string]any](t, body)
	if status != http.StatusOK || user["id"] != float64(githubUser.ID) || user["login"] != githubUser.Login || user["email"] != nil {
		t.Errorf("/user = %d %s, want 200 id=%d login=%s email=null", status, body, githubUser.ID, githubUser.Login)
	}
	status, body = f.getWithToken("/user/emails", token["access_token"])
	if got := decode[[]fakeoidc.GitHubEmail](t, body); status != http.StatusOK || !reflect.DeepEqual(got, githubUser.Emails) {
		t.Errorf("/user/emails = %d %+v, want 200 %+v", status, got, githubUser.Emails)
	}
	for _, path := range []string{"/user", "/user/emails"} {
		if status, _ := f.getWithToken(path, "fakeoidc-token-unknown"); status != http.StatusUnauthorized {
			t.Errorf("知らないアクセストークンの %s = %d, want 401", path, status)
		}
	}
	// GitHub のアクセストークンでは Google の口を読めない
	if status, _ := f.getWithToken("/v1/userinfo", token["access_token"]); status != http.StatusUnauthorized {
		t.Errorf("GitHub のアクセストークンの Google の userinfo = %d, want 401", status)
	}
}

// TestGitHubToken_FormEncodedAndErrors は、GitHub の文書のとおり、Accept が JSON を求めないときは URL の形で
// 符号化した本文で返し、誤りを本文の error で返すことを確かめる。
func TestGitHubToken_FormEncodedAndErrors(t *testing.T) {
	f := newFixture(t)
	f.putUser(fakeoidc.GitHub, githubUser)
	code := f.authorize("/login/oauth/authorize", githubAuthParams("s")).Query().Get("code")

	status, header, body := f.postToken("/login/oauth/access_token", tokenForm(fakeoidc.GitHub, code), "")
	values, err := url.ParseQuery(string(body))
	if err != nil || status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "application/x-www-form-urlencoded") ||
		values.Get("access_token") == "" || values.Get("token_type") != "bearer" {
		t.Errorf("Accept の無い access_token の口 = %d %q %s, want URL の形の本文のアクセストークン", status, header.Get("Content-Type"), body)
	}

	tests := []struct {
		name      string
		form      url.Values
		wantError string
	}{
		{"使い済みのコード", tokenForm(fakeoidc.GitHub, code), "bad_verification_code"},
		{"クライアントの秘密の値が違う", func() url.Values {
			form := tokenForm(fakeoidc.GitHub, "fakeoidc-code-unknown")
			form.Set("client_secret", "wrong")
			return form
		}(), "incorrect_client_credentials"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			status, _, body := f.postToken("/login/oauth/access_token", tc.form, "application/json")
			if got := decode[map[string]string](t, body); status != http.StatusOK || got["error"] != tc.wantError || got["access_token"] != "" {
				t.Errorf("access_token の口 = %d %s, want 200 error=%s", status, body, tc.wantError)
			}
		})
	}
}

// TestAuthorize_RejectsBadRequests は、認可の口が、正しくない要求と、クライアントや利用者を登録する前の要求を断ることを確かめる。
func TestAuthorize_RejectsBadRequests(t *testing.T) {
	f := newBareFixture(t)
	if status, _, _ := f.do(f.request(http.MethodGet, "/o/oauth2/v2/auth?"+googleAuthParams("s").Encode(), http.NoBody)); status != http.StatusBadRequest {
		t.Errorf("クライアントを登録する前の認可の口 = %d, want 400", status)
	}
	for _, tc := range []struct {
		name, provider, body string
		want                 int
	}{
		{"知らない提供元", "twitter", "client_id=x", http.StatusNotFound},
		{"知らない項目がある", fakeoidc.Google, "client_id=x&unknown=1", http.StatusBadRequest},
	} {
		req := f.request(http.MethodPut, "/_compat/clients/"+tc.provider, strings.NewReader(tc.body))
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		if status, _, body := f.do(req); status != tc.want {
			t.Errorf("%sクライアントの登録 = %d %s, want %d", tc.name, status, body, tc.want)
		}
	}
	f.putClient(fakeoidc.Google, testClient(fakeoidc.Google))
	if status, _, _ := f.do(f.request(http.MethodGet, "/o/oauth2/v2/auth?"+googleAuthParams("s").Encode(), http.NoBody)); status != http.StatusConflict {
		t.Errorf("利用者を登録する前の認可の口 = %d, want 409", status)
	}
	f.putUser(fakeoidc.Google, googleUser)

	tests := []struct {
		name   string
		change func(url.Values)
	}{
		{"client_id が違う", func(v url.Values) { v.Set("client_id", testClient(fakeoidc.GitHub).ID) }},
		{"redirect_uri が無い", func(v url.Values) { v.Del("redirect_uri") }},
		{"redirect_uri が登録した転送先に無い", func(v url.Values) { v.Set("redirect_uri", "http://evil.example/api/auth/oidc/callback") }},
		{"response_type が code でない", func(v url.Values) { v.Set("response_type", "token") }},
		{"code_challenge_method が S256 でない", func(v url.Values) { v.Set("code_challenge_method", "plain") }},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			params := googleAuthParams("s")
			tc.change(params)
			if status, _, body := f.do(f.request(http.MethodGet, "/o/oauth2/v2/auth?"+params.Encode(), http.NoBody)); status != http.StatusBadRequest {
				t.Errorf("認可の口 = %d %s, want 400", status, body)
			}
		})
	}

	if status, _, _ := f.do(f.request(http.MethodPut, "/_compat/users/google", strings.NewReader(`{"sub":"x","unknown":1}`))); status != http.StatusBadRequest {
		t.Errorf("知らない項目のある利用者の登録 = %d, want 400", status)
	}
}

// TestUnknownPath_Returns501AndLog は、受けると決めていない口を 501 で断り、fakeoidc_unexpected_request をログに出すことを確かめる。
func TestUnknownPath_Returns501AndLog(t *testing.T) {
	f := newFixture(t)
	logs := captureLog(t)
	if status, _, _ := f.do(f.request(http.MethodGet, "/.well-known/openid-configuration", http.NoBody)); status != http.StatusNotImplemented {
		t.Errorf("/.well-known/openid-configuration = %d, want 501", status)
	}
	if got := logs.String(); !strings.Contains(got, `"msg":"fakeoidc_unexpected_request"`) || !strings.Contains(got, `"uri":"/.well-known/openid-configuration"`) {
		t.Errorf("ログ = %s, want fakeoidc_unexpected_request の行", got)
	}
}

// TestImage_ServesOnNetwork は、Dockerfile で組み立てたイメージが、ポート 8080 で認可の口を受けることを確かめる。
func TestImage_ServesOnNetwork(t *testing.T) {
	root, err := harness.RepoRoot()
	if err != nil {
		t.Fatal(err)
	}
	ctx := t.Context()
	var buildLog bytes.Buffer
	images, err := harness.BuildImages(ctx, root, &buildLog, harness.ImageFakeOIDC)
	t.Cleanup(func() {
		if err := images.Remove(context.Background()); err != nil {
			t.Errorf("組み立てたイメージを消せません: %v", err)
		}
	})
	if err != nil {
		t.Fatalf("BuildImages: %v\n%s", err, buildLog.String())
	}
	env, err := harness.NewEnv(ctx)
	if err != nil {
		t.Fatal(err)
	}
	env.Cleanup(t)
	c, err := env.Start(ctx, harness.ContainerSpec{
		Name:         "fakeoidc",
		Image:        images[harness.ImageFakeOIDC],
		ExposedPorts: []string{fakeoidc.Port + "/tcp"},
	})
	if err != nil {
		t.Fatal(err)
	}
	baseURL, err := c.BaseURL(ctx, fakeoidc.Port+"/tcp")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := harness.WaitHealthz(ctx, harness.NewHTTPClient(), baseURL+"/_compat", time.Now()); err != nil {
		t.Fatal(err)
	}

	f := fixture{t: t, base: baseURL, client: noRedirectClient()}
	f.putClient(fakeoidc.Google, testClient(fakeoidc.Google))
	f.putUser(fakeoidc.Google, googleUser)
	if code := f.authorize("/o/oauth2/v2/auth", googleAuthParams("s")).Query().Get("code"); code == "" {
		t.Error("コンテナの認可の口が、認可のコードを付けずに転送しました")
	}
	logs, err := c.Logs(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = logs.Close() }()
	text, _ := io.ReadAll(logs)
	if !slices.ContainsFunc(strings.Split(string(text), "\n"), func(l string) bool { return strings.Contains(l, "ポート 8080 で受けます") }) {
		t.Errorf("コンテナのログ = %q, want 起動の行", text)
	}
}

// syncBuffer は、サーバの処理とテストの処理が同時に読み書きできる bytes.Buffer である。
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// captureLog は、テストのあいだ、slog の既定の出力を JSON の形で読めるようにする。
func captureLog(t *testing.T) *syncBuffer {
	t.Helper()
	logs := &syncBuffer{}
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(logs, nil)))
	t.Cleanup(func() { slog.SetDefault(previous) })
	return logs
}
