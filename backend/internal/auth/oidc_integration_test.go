package auth

import (
	"encoding/base64"
	"encoding/binary"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"reflect"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// rfc7636Octets は、RFC 7636 の付録 B の例の code_verifier の32バイトである。
var rfc7636Octets = []byte{
	116, 24, 223, 180, 151, 153, 224, 37, 79, 250, 96, 125, 216, 173, 187, 186,
	22, 212, 37, 77, 105, 214, 191, 240, 91, 88, 5, 88, 83, 132, 141, 121,
}

const (
	// rfc7636Verifier と rfc7636Challenge は、RFC 7636 の付録 B の例の code_verifier と、その S256 の code_challenge である。
	rfc7636Verifier  = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
	rfc7636Challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
	// testCallbackURI は、Java 版の開発環境の認証の受け口が作る戻り先の URL である。
	testCallbackURI = "http://localhost:8080/api/auth/oidc/callback"
)

// testOIDCConfig は、Java 版の application.yaml と同じログインの開始の接続先と scope に、テストのクライアントの ID を
// 足した設定である。
func testOIDCConfig() config.OIDC {
	return config.OIDC{
		Google: config.Provider{
			AuthURL:  "https://accounts.google.com/o/oauth2/v2/auth",
			Scopes:   "openid email profile",
			ClientID: "google-client-id",
		},
		GitHub: config.Provider{
			AuthURL:  "https://github.com/login/oauth/authorize",
			Scopes:   "read:user user:email",
			ClientID: "github-client-id",
		},
	}
}

// newOIDCService は、テストの Valkey と testOIDCConfig の設定と、乱数の関数 random を使う Service と、
// Redis に直に読み書きするクライアントを作る。
func newOIDCService(t *testing.T, random func([]byte) (int, error)) (*Service, redis.UniversalClient) {
	t.Helper()
	client := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	t.Cleanup(func() { _ = client.Close() })
	return New(Deps{Redis: client, OIDC: testOIDCConfig(), Random: random}), client
}

// oidcStartRandom は、1つ目の32バイトに RFC 7636 の例の code_verifier のバイトを、2つ目の32バイトにテストごとに違う
// バイトを返す乱数の関数と、2つ目の32バイトから作られる state を返す。Java 版の StartOidcAuthorizationUseCase は、
// code_verifier を先に、state をあとに作る。
func oidcStartRandom() (func([]byte) (int, error), string) {
	a, b := uuid.New(), uuid.New()
	stateBytes := append(a[:], b[:]...)
	raw := append(append([]byte{}, rfc7636Octets...), stateBytes...)
	return fixedRandom(raw), base64.RawURLEncoding.EncodeToString(stateBytes)
}

// oidcKeys は、state の3つの記録のキーを返す。
func oidcKeys(state string) []string {
	return []string{"oidc:state:" + state, "oidc:provider:" + state, "oidc:code_verifier:" + state}
}

// TestStartOIDC_URLParamsOrder は、ログインの開始の URL が、Java 版の OidcClient と同じく、接続先のあとに
// client_id、response_type、scope、redirect_uri、state、code_challenge、code_challenge_method をこの順に並べ、
// Spring の UriComponentsBuilder と同じく scope の空白を %20 にし、redirect_uri の : と / を残すことを確かめる。
// code_challenge は code_verifier の SHA-256 の base64url である。provider の大文字と小文字は、
// Java 版の OidcProviderFactory と同じく区別しない(要件1.3)。
func TestStartOIDC_URLParamsOrder(t *testing.T) {
	cases := []struct {
		name, provider, prefix, scope string
	}{
		{"google", "google", "https://accounts.google.com/o/oauth2/v2/auth?client_id=google-client-id", "openid%20email%20profile"},
		{"github", "github", "https://github.com/login/oauth/authorize?client_id=github-client-id", "read:user%20user:email"},
		{"大文字の混じった Google", "Google", "https://accounts.google.com/o/oauth2/v2/auth?client_id=google-client-id", "openid%20email%20profile"},
		{"大文字だけの GITHUB", "GITHUB", "https://github.com/login/oauth/authorize?client_id=github-client-id", "read:user%20user:email"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			random, state := oidcStartRandom()
			s, _ := newOIDCService(t, random)
			got, err := s.StartOIDC(t.Context(), c.provider, testCallbackURI)
			if err != nil {
				t.Fatalf("StartOIDC: %v", err)
			}
			want := c.prefix + "&response_type=code&scope=" + c.scope +
				"&redirect_uri=http://localhost:8080/api/auth/oidc/callback&state=" + state +
				"&code_challenge=" + rfc7636Challenge + "&code_challenge_method=S256"
			if got != want {
				t.Errorf("URL =\n%s\nwant\n%s", got, want)
			}
		})
	}
}

// TestStartOIDC_StoresStateFor10Minutes は、Java 版の RedisOidcAuthorizationSessionStore と同じく、
// oidc:state:<state> に state を、oidc:provider:<state> に受けたままの provider を、oidc:code_verifier:<state> に
// code_verifier を、どれも JSON の文字列で10分置くことを確かめる(要件3.7、要件4.2)。
func TestStartOIDC_StoresStateFor10Minutes(t *testing.T) {
	for _, provider := range []string{"google", "github", "GitHub"} {
		t.Run(provider, func(t *testing.T) {
			random, state := oidcStartRandom()
			s, client := newOIDCService(t, random)
			if _, err := s.StartOIDC(t.Context(), provider, testCallbackURI); err != nil {
				t.Fatalf("StartOIDC: %v", err)
			}
			keys := oidcKeys(state)
			wants := []string{`"` + state + `"`, `"` + provider + `"`, `"` + rfc7636Verifier + `"`}
			for i, key := range keys {
				if got := mustGetRaw(t, client, key); got != wants[i] {
					t.Errorf("%s = %s, want %s", key, got, wants[i])
				}
				assertTTL(t, client, key, 10*time.Minute)
			}
		})
	}
}

// TestStartOIDC_UnknownProvider400 は、Google と GitHub のほかの provider を、Java 版のように記録を置いてから 500 で
// 答えるのではなく、記録を置かずに 400 の「入力エラーがあります。」で断ることを確かめる(要件5.5)。
func TestStartOIDC_UnknownProvider400(t *testing.T) {
	for _, provider := range []string{"twitter", "", "googlee", " google", "git hub"} {
		t.Run("provider="+provider, func(t *testing.T) {
			random, state := oidcStartRandom()
			s, client := newOIDCService(t, random)
			got, err := s.StartOIDC(t.Context(), provider, testCallbackURI)
			wantStatusError(t, err, 400, MessageInvalidInput, "")
			if got != "" {
				t.Errorf("URL = %q, want 空", got)
			}
			for _, key := range oidcKeys(state) {
				if keyExists(t, client, key) {
					t.Errorf("%s の記録が残った", key)
				}
			}
		})
	}
}

// TestStartOIDC_Failures は、乱数を読めないときと Redis に置けないときに、URL を返さず、400 ではない誤りを返すことを確かめる。
func TestStartOIDC_Failures(t *testing.T) {
	t.Run("乱数を読めない", func(t *testing.T) {
		s, _ := newOIDCService(t, func([]byte) (int, error) { return 0, errors.New("乱数の誤り") })
		got, err := s.StartOIDC(t.Context(), "google", testCallbackURI)
		wantServerError(t, got, err)
	})
	t.Run("state を作る乱数を読めない", func(t *testing.T) {
		s, client := newOIDCService(t, fixedRandom(rfc7636Octets))
		got, err := s.StartOIDC(t.Context(), "google", testCallbackURI)
		wantServerError(t, got, err)
		if n, err := client.Exists(t.Context(), "oidc:state:", "oidc:provider:", "oidc:code_verifier:").Result(); err != nil || n != 0 {
			t.Errorf("空の state の記録 = %d, %v, want 0", n, err)
		}
	})
	t.Run("Redis に置けない", func(t *testing.T) {
		random, _ := oidcStartRandom()
		s, client := newOIDCService(t, random)
		_ = client.Close()
		got, err := s.StartOIDC(t.Context(), "google", testCallbackURI)
		wantServerError(t, got, err)
	})
}

// wantServerError は、StartOIDC が URL を返さず、*Error ではない誤り(受け口が 500 で答える誤り)を返したことを確かめる。
func wantServerError(t *testing.T, url string, err error) {
	t.Helper()
	var e *Error
	if err == nil || errors.As(err, &e) {
		t.Errorf("誤り = %v, want *Error ではない誤り", err)
	}
	if url != "" {
		t.Errorf("URL = %q, want 空", url)
	}
}

const (
	// oidcGrant は、偽の Google と GitHub がコードの交換で返すアクセストークンの値である。
	oidcGrant = "fake-grant-0123456789"
	// oidcCode は、Google か GitHub が戻り先に付けるコードの値である。
	oidcCode = "fake-code-0123456789"
	// githubEmailsURL は、Java 版の GithubOidcProvider がメールアドレスの一覧を読む URL である。
	githubEmailsURL = "https://api.github.com/user/emails"
	// oidcName は、テストの利用者の名前である。Java 版の FreeMarker は、HTML の特別な文字をそのまま差し込む。
	oidcName = "山田<&>太郎"
)

// oidcGrantReply は、偽の Google と GitHub のコードの交換の応答の本文である。
var oidcGrantReply = `{"access_token":"` + oidcGrant + `","token_type":"Bearer","expires_in":3599,` +
	`"scope":"openid email","id_token":"a.b.c"}`

// testGoogleClientValue と testGitHubClientValue は、テストのクライアントの秘密の値である。
var (
	testGoogleClientValue = uuid.NewString()
	testGitHubClientValue = uuid.NewString()
)

// fakeReply は、偽のサーバの1つの道の答えである。contentType が空なら Content-Type を書かない。
type fakeReply struct {
	status      int
	contentType string
	body        string
}

// jsonReply は、200 と application/json の答えである。
func jsonReply(body string) fakeReply {
	return fakeReply{status: http.StatusOK, contentType: "application/json", body: body}
}

// fakeRequest は、偽のサーバが受けた要求である。
type fakeRequest struct {
	method string
	header http.Header
	form   url.Values
}

// fakeOIDC は、Google と GitHub の代わりに、コードの交換と利用者の情報とメールアドレスの一覧に答える httptest のサーバである。
// 道は、/google/token、/google/userinfo、/github/token、/github/user、/user/emails である。
type fakeOIDC struct {
	srv      *httptest.Server
	mu       sync.Mutex
	replies  map[string]fakeReply
	requests map[string][]fakeRequest
	// urls は、Service の HTTP のクライアントが送った要求の、書き換える前の URL である。
	urls []string
}

func newFakeOIDC(t *testing.T) *fakeOIDC {
	t.Helper()
	f := &fakeOIDC{replies: map[string]fakeReply{}, requests: map[string][]fakeRequest{}}
	f.srv = httptest.NewServer(http.HandlerFunc(f.serve))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeOIDC) serve(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	form, _ := url.ParseQuery(string(body))
	f.mu.Lock()
	f.requests[r.URL.Path] = append(f.requests[r.URL.Path], fakeRequest{method: r.Method, header: r.Header.Clone(), form: form})
	reply, ok := f.replies[r.URL.Path]
	f.mu.Unlock()
	if !ok {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	if reply.contentType != "" {
		w.Header().Set("Content-Type", reply.contentType)
	} else {
		w.Header()["Content-Type"] = nil
	}
	w.WriteHeader(reply.status)
	_, _ = io.WriteString(w, reply.body)
}

// reply は、道 path の答えを決める。
func (f *fakeOIDC) reply(path string, r fakeReply) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.replies[path] = r
}

// received は、道 path が受けた要求を返す。
func (f *fakeOIDC) received(path string) []fakeRequest {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Clone(f.requests[path])
}

// sentURLs は、Service の HTTP のクライアントが送った要求の URL を返す。
func (f *fakeOIDC) sentURLs() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Clone(f.urls)
}

// RoundTrip は、要求の URL を覚え、api.github.com への要求を偽のサーバに送り直す。
func (f *fakeOIDC) RoundTrip(r *http.Request) (*http.Response, error) {
	f.mu.Lock()
	f.urls = append(f.urls, r.URL.String())
	f.mu.Unlock()
	if r.URL.Host == "api.github.com" {
		target, err := url.Parse(f.srv.URL)
		if err != nil {
			return nil, err
		}
		r = r.Clone(r.Context())
		r.URL.Scheme = target.Scheme
		r.URL.Host = target.Host
		r.Host = target.Host
	}
	return http.DefaultTransport.RoundTrip(r)
}

// newOIDCCallbackService は、テストのデータベースと Valkey と偽の SES と、偽の Google と GitHub を使い、
// 今の時刻を completionNow に決めた Service を作る。
func newOIDCCallbackService(t *testing.T, random func([]byte) (int, error)) (*Service, redis.UniversalClient, *fakeSES, *fakeOIDC) {
	t.Helper()
	templates, err := backend.MailTemplates()
	if err != nil {
		t.Fatal(err)
	}
	f := newFakeOIDC(t)
	client := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	t.Cleanup(func() { _ = client.Close() })
	mailer := &fakeSES{}
	oidc := testOIDCConfig()
	oidc.Google.TokenURL = f.srv.URL + "/google/token"
	oidc.Google.UserInfoURL = f.srv.URL + "/google/userinfo"
	oidc.Google.ClientSecret = testGoogleClientValue
	oidc.GitHub.TokenURL = f.srv.URL + "/github/token"
	oidc.GitHub.UserInfoURL = f.srv.URL + "/github/user"
	oidc.GitHub.ClientSecret = testGitHubClientValue
	return New(Deps{
		Pool:          testPool,
		Redis:         client,
		SES:           mailer,
		App:           javaDevApp(t),
		JWT:           config.JWT{Secret: testSigningKey, AccessTokenValidity: 10 * time.Minute, RefreshTokenValidity: refreshValidity},
		MailTemplates: templates,
		OIDC:          oidc,
		HTTPClient:    &http.Client{Transport: f, Timeout: 10 * time.Second},
		Now:           func() time.Time { return completionNow },
		Random:        random,
	}), client, mailer, f
}

// oidcLoginRandom は、1つ目の16バイトを連携の行の ID に、2つ目の16バイトを利用者の ID にする乱数の関数と、
// その2つの ID を返す。Java 版の OidcLoginUseCase は、連携の ID を先に、利用者の ID をあとに作る。
// 続く32バイトは、ログインを続けるための値に使われる。
func oidcLoginRandom() (func([]byte) (int, error), uuid.UUID, uuid.UUID) {
	pid, uid, a, b := uuid.New(), uuid.New(), uuid.New(), uuid.New()
	return fixedRandom(slices.Concat(pid[:], uid[:], a[:], b[:])), pid, uid
}

// putOIDCSession は、StartOIDC と同じ形で、provider のログインの開始の記録を置き、state を返す。
func putOIDCSession(t *testing.T, s *Service, provider string) string {
	t.Helper()
	_, state := uniqueRandom()
	if err := s.storeOIDCSession(t.Context(), state, provider, rfc7636Verifier); err != nil {
		t.Fatal(err)
	}
	return state
}

// callback は、コードと state を付けて HandleOIDCCallback を呼ぶ。
func callback(t *testing.T, s *Service, state string) OIDCCallbackResult {
	t.Helper()
	code := oidcCode
	return s.HandleOIDCCallback(t.Context(), &code, &state, nil, testCallbackURI)
}

// uniqueNumber は、GitHub の利用者の ID に使う、テストごとに違う数の文字の並びを返す。
func uniqueNumber() string {
	u := uuid.New()
	return strconv.FormatUint(binary.BigEndian.Uint64(u[:8])>>2, 10)
}

// someTextPtr は、p が nil なら NULL の、そうでなければ p の文字列の列の値を作る。
func someTextPtr(p *string) pgtype.Text {
	if p == nil {
		return pgtype.Text{}
	}
	return someText(*p)
}

// strPtr は、s を指すポインタを返す。
func strPtr(s string) *string {
	return &s
}

// loginFailedURL と userInfoFailedURL と unverifiedURL は、失敗したときに移る先である。文言は Java の URLEncoder.encode で
// エスケープする。2つの文言は * と ~ を含まないので、url.QueryEscape と同じ結果になる。
func loginFailedURL(t *testing.T) string {
	return javaDevApp(t).FrontendBaseURL + "/login?error=" + url.QueryEscape(MessageOIDCFailed)
}

func userInfoFailedURL(t *testing.T) string {
	return javaDevApp(t).FrontendBaseURL + "/login?error=" + url.QueryEscape(MessageOIDCUserInfoFailed)
}

func unverifiedURL(t *testing.T) string {
	return javaDevApp(t).FrontendBaseURL + "/login?error=unverified_email"
}

// wantKeysRemoved は、state の3つの記録が消えたことを確かめる。
func wantKeysRemoved(t *testing.T, client redis.UniversalClient, state string) {
	t.Helper()
	for _, key := range oidcKeys(state) {
		if keyExists(t, client, key) {
			t.Errorf("%s の記録が残った", key)
		}
	}
}

// wantFailure は、結果が、移る先 location の失敗で、ログインの状態の値を持たないことを確かめる。
func wantFailure(t *testing.T, got OIDCCallbackResult, location string) {
	t.Helper()
	if got.Location != location {
		t.Errorf("移る先 = %q, want %q", got.Location, location)
	}
	if got.Session != (SessionTokens{}) {
		t.Errorf("ログインの状態の値 = %+v, want 空", got.Session)
	}
	if got.Cause == nil {
		t.Error("失敗の元の誤りが無い")
	}
}

// wantLoggedIn は、結果が、画面の /resume/list に移るログインの終わりで、ログインの状態の値が利用者 id と役割 roles と
// 世代の番号 version を表すことを確かめる。
func wantLoggedIn(t *testing.T, s *Service, got OIDCCallbackResult, id uuid.UUID, roles []string, version int64) {
	t.Helper()
	if want := s.deps.App.FrontendBaseURL + "/resume/list"; got.Location != want {
		t.Fatalf("移る先 = %q, want %q(誤り %v)", got.Location, want, got.Cause)
	}
	if got.Cause != nil {
		t.Errorf("失敗の元の誤り = %v, want nil", got.Cause)
	}
	wantSession(t, s, got.Session, id, roles, version)
}

// wantGrantRequest は、道 path が、Java 版の OidcClient と同じコードの交換の要求を1回受けたことを確かめる。
func wantGrantRequest(t *testing.T, f *fakeOIDC, path, clientID, clientValue string) {
	t.Helper()
	got := f.received(path)
	if len(got) != 1 {
		t.Fatalf("%s の要求 = %d 回, want 1 回", path, len(got))
	}
	r := got[0]
	if r.method != http.MethodPost {
		t.Errorf("%s の要求の方法 = %s, want POST", path, r.method)
	}
	if ct := r.header.Get("Content-Type"); !strings.HasPrefix(ct, "application/x-www-form-urlencoded") {
		t.Errorf("%s の Content-Type = %q", path, ct)
	}
	if a := r.header.Get("Accept"); a != "application/json" {
		t.Errorf("%s の Accept = %q, want application/json", path, a)
	}
	want := url.Values{
		"grant_type":    {"authorization_code"},
		"code":          {oidcCode},
		"redirect_uri":  {testCallbackURI},
		"code_verifier": {rfc7636Verifier},
		"client_id":     {clientID},
		"client_secret": {clientValue},
	}
	if !reflect.DeepEqual(r.form, want) {
		t.Errorf("%s の本文 = %v, want %v", path, r.form, want)
	}
}

// wantUserInfoRequest は、道 path が、アクセストークンを付けた GET の要求を1回受けたことを確かめる。
// github が真なら、Java 版の GithubOidcProvider の configureHeaders が足す2つのヘッダも確かめる。
func wantUserInfoRequest(t *testing.T, f *fakeOIDC, path string, github bool) {
	t.Helper()
	got := f.received(path)
	if len(got) != 1 {
		t.Fatalf("%s の要求 = %d 回, want 1 回", path, len(got))
	}
	r := got[0]
	if r.method != http.MethodGet {
		t.Errorf("%s の要求の方法 = %s, want GET", path, r.method)
	}
	if a := r.header.Get("Authorization"); a != "Bearer "+oidcGrant {
		t.Errorf("%s の Authorization = %q", path, a)
	}
	if github {
		if a := r.header.Get("Accept"); a != "application/vnd.github+json" {
			t.Errorf("%s の Accept = %q", path, a)
		}
		if v := r.header.Get("X-GitHub-Api-Version"); v != "2022-11-28" {
			t.Errorf("%s の X-GitHub-Api-Version = %q", path, v)
		}
	}
}

// wantRegisteredMail は、偽の SES が、email に登録の完了のメールを1通だけ受けたことを確かめる。
func wantRegisteredMail(t *testing.T, s *Service, mailer *fakeSES, email string) {
	t.Helper()
	if len(mailer.got) != 1 {
		t.Fatalf("メールの送り出し = %d 回, want 1 回", len(mailer.got))
	}
	in := mailer.got[0]
	if strings.Join(in.Destination.ToAddresses, ",") != email {
		t.Errorf("宛先 = %v, want %s", in.Destination.ToAddresses, email)
	}
	if want := "【" + s.deps.App.SiteName + "】新規登録完了のお知らせ"; deref(in.Message.Subject.Data) != want {
		t.Errorf("件名 = %q, want %q", deref(in.Message.Subject.Data), want)
	}
	if body := mailedBody(t, mailer, 0); !strings.Contains(body, oidcName+" 様") {
		t.Errorf("本文 = %q, want 利用者の名前 %q を含む", body, oidcName)
	}
}

// googleUserInfo は、Google の利用者の情報の応答の本文である。
func googleUserInfo(sub, email string) string {
	return `{"sub":"` + sub + `","email":"` + email + `","email_verified":true,"name":"` + oidcName + `","picture":"https://example.com/a.png"}`
}

// githubUser は、GitHub の利用者の情報の応答の本文である。email は、Java 版と同じく使わない。
func githubUser(id string) string {
	return `{"id":` + id + `,"login":"` + oidcName + `","email":"public-` + id + `@example.com","name":"other"}`
}

// githubEmails は、主で確認済みのメールアドレスが email の、GitHub のメールアドレスの一覧の応答の本文である。
func githubEmails(email string) string {
	return `[{"email":"other-` + email + `","primary":false,"verified":true,"visibility":null},` +
		`{"email":"` + email + `","primary":true,"verified":true,"visibility":"private"}]`
}

// TestHandleOIDCCallback_NewUser は、Google か GitHub の利用者の ID でつないだアカウントも、同じメールアドレスの
// アカウントも無いとき、Java 版の OidcLoginUseCase と同じく、新しいアカウントを作ってログインを終え、画面の /resume/list に
// 移すことを確かめる(要件1.3)。連携の行の ID を先に、利用者の ID をあとに作り、確認済みのメールアドレスと役割 USER と、
// 世代の番号 0 の行を足し、メールアドレスがあれば登録の完了のメールを送る。state の3つの記録は消す。
func TestHandleOIDCCallback_NewUser(t *testing.T) {
	now := javaWallClock(completionNow)
	t.Run("Google", func(t *testing.T) {
		random, pid, uid := oidcLoginRandom()
		s, client, mailer, f := newOIDCCallbackService(t, random)
		email, sub := uniqueEmail(), uuid.NewString()
		f.reply("/google/token", jsonReply(oidcGrantReply))
		f.reply("/google/userinfo", jsonReply(googleUserInfo(sub, email)))
		state := putOIDCSession(t, s, "Google")
		got := callback(t, s, state)
		wantLoggedIn(t, s, got, uid, []string{"USER"}, 0)
		wantRows(t, uid, storedRows{
			Found: true,
			User: userRow{
				Email: someText(email), Username: someText(oidcName),
				CreatedAt: now, UpdatedAt: now, EmailVerifiedAt: now,
			},
			Roles:      []string{"USER"},
			Providers:  []providerRow{{ID: pid, Name: "google", ProviderUserID: sub, CreatedAt: now, UpdatedAt: now}},
			HasVersion: true,
			VersionAt:  now.Time,
		})
		wantRegisteredMail(t, s, mailer, email)
		wantKeysRemoved(t, client, state)
		wantGrantRequest(t, f, "/google/token", "google-client-id", testGoogleClientValue)
		wantUserInfoRequest(t, f, "/google/userinfo", false)
		if urls := f.sentURLs(); slices.Contains(urls, githubEmailsURL) {
			t.Errorf("Google のログインで GitHub のメールアドレスの一覧を読んだ: %v", urls)
		}
	})
	t.Run("GitHub", func(t *testing.T) {
		random, pid, uid := oidcLoginRandom()
		s, client, mailer, f := newOIDCCallbackService(t, random)
		email, id := uniqueEmail(), uniqueNumber()
		f.reply("/github/token", jsonReply(oidcGrantReply))
		f.reply("/github/user", jsonReply(githubUser(id)))
		f.reply("/user/emails", jsonReply(githubEmails(email)))
		state := putOIDCSession(t, s, "GITHUB")
		got := callback(t, s, state)
		wantLoggedIn(t, s, got, uid, []string{"USER"}, 0)
		wantRows(t, uid, storedRows{
			Found: true,
			User: userRow{
				Email: someText(email), Username: someText(oidcName),
				CreatedAt: now, UpdatedAt: now, EmailVerifiedAt: now,
			},
			Roles:      []string{"USER"},
			Providers:  []providerRow{{ID: pid, Name: "github", ProviderUserID: id, CreatedAt: now, UpdatedAt: now}},
			HasVersion: true,
			VersionAt:  now.Time,
		})
		wantRegisteredMail(t, s, mailer, email)
		wantKeysRemoved(t, client, state)
		wantGrantRequest(t, f, "/github/token", "github-client-id", testGitHubClientValue)
		wantUserInfoRequest(t, f, "/github/user", true)
		wantUserInfoRequest(t, f, "/user/emails", true)
		if urls := f.sentURLs(); !slices.Contains(urls, githubEmailsURL) {
			t.Errorf("要求の URL = %v, want %s を含む", urls, githubEmailsURL)
		}
	})
	t.Run("確認済みでない Google のメールアドレスは使わない", func(t *testing.T) {
		random, pid, uid := oidcLoginRandom()
		s, _, mailer, f := newOIDCCallbackService(t, random)
		sub := uuid.NewString()
		f.reply("/google/token", jsonReply(oidcGrantReply))
		f.reply("/google/userinfo", jsonReply(`{"sub":"`+sub+`","email":"`+uniqueEmail()+`","email_verified":false,"name":""}`))
		got := callback(t, s, putOIDCSession(t, s, "google"))
		wantLoggedIn(t, s, got, uid, []string{"USER"}, 0)
		// 名前の空の文字列は、NULL にせず、そのまま書く。
		wantRows(t, uid, storedRows{
			Found:      true,
			User:       userRow{Username: someText(""), CreatedAt: now, UpdatedAt: now},
			Roles:      []string{"USER"},
			Providers:  []providerRow{{ID: pid, Name: "google", ProviderUserID: sub, CreatedAt: now, UpdatedAt: now}},
			HasVersion: true,
			VersionAt:  now.Time,
		})
		if len(mailer.got) != 0 {
			t.Errorf("メールの送り出し = %d 回, want 0 回", len(mailer.got))
		}
	})
	failures := []struct{ name, userInfo string }{
		// Java 版の FreeMarker は、null の名前を差し込めずに例外にし、トランザクションを取り消す。
		{"名前の無い利用者には登録の完了のメールを作れない", `{"sub":"S","email":"E","email_verified":true}`},
		{"null の名前の利用者には登録の完了のメールを作れない", `{"sub":"S","email":"E","email_verified":true,"name":null}`},
		{"Google の利用者の ID が無い", `{"email":"E","email_verified":true,"name":"n"}`},
		{"Google の利用者の ID が空白だけ", `{"sub":" \t","email":"E","email_verified":true,"name":"n"}`},
		{"Commons の確かめを通らないメールアドレス", `{"sub":"S","email":"user@localhost","email_verified":true,"name":"n"}`},
	}
	for _, c := range failures {
		t.Run(c.name, func(t *testing.T) {
			random, pid, uid := oidcLoginRandom()
			s, client, mailer, f := newOIDCCallbackService(t, random)
			body := strings.ReplaceAll(strings.ReplaceAll(c.userInfo, `"S"`, `"`+uuid.NewString()+`"`), `"E"`, `"`+uniqueEmail()+`"`)
			f.reply("/google/token", jsonReply(oidcGrantReply))
			f.reply("/google/userinfo", jsonReply(body))
			state := putOIDCSession(t, s, "google")
			wantFailure(t, callback(t, s, state), loginFailedURL(t))
			wantRows(t, uid, noRows)
			var n int
			if err := testPool.QueryRow(t.Context(), `SELECT count(*) FROM user_auth_providers WHERE id = $1::uuid`, pid.String()).Scan(&n); err != nil || n != 0 {
				t.Errorf("連携の行 = %d, %v, want 無い", n, err)
			}
			if len(mailer.got) != 0 {
				t.Errorf("メールの送り出し = %d 回, want 0 回", len(mailer.got))
			}
			wantKeysRemoved(t, client, state)
		})
	}
}

// TestHandleOIDCCallback_LinkExisting は、Java 版の OidcLoginUseCase と同じく、Google か GitHub の利用者の ID でつないだ
// アカウントがあればそのアカウントで、無ければ確認済みの同じメールアドレスのアカウントにつないでログインを終えることを
// 確かめる(要件1.3)。
func TestHandleOIDCCallback_LinkExisting(t *testing.T) {
	now := javaWallClock(completionNow)
	verifiedUser := func(email string) userRow {
		return userRow{
			Email: someText(email), Password: someText(javaBcryptSample), Username: someText("既存の人"),
			CreatedAt: oldStamp, UpdatedAt: oldStamp, EmailVerifiedAt: oldStamp,
		}
	}
	t.Run("確認済みの同じメールアドレスのアカウントにつなぐ", func(t *testing.T) {
		random, pid, _ := oidcLoginRandom()
		s, client, mailer, f := newOIDCCallbackService(t, random)
		id, email, sub := uuid.New(), uniqueEmail(), uuid.NewString()
		u := verifiedUser(email)
		insertStoredUser(t, id, u, []string{"USER"}, nil, 3)
		f.reply("/google/token", jsonReply(oidcGrantReply))
		f.reply("/google/userinfo", jsonReply(googleUserInfo(sub, email)))
		state := putOIDCSession(t, s, "google")
		got := callback(t, s, state)
		wantLoggedIn(t, s, got, id, []string{"USER"}, 3)
		u.UpdatedAt = now
		wantRows(t, id, storedRows{
			Found: true, User: u, Roles: []string{"USER"},
			Providers:  []providerRow{{ID: pid, Name: "google", ProviderUserID: sub, CreatedAt: now, UpdatedAt: now}},
			HasVersion: true, Version: 3, VersionAt: oldStamp.Time,
		})
		if len(mailer.got) != 0 {
			t.Errorf("メールの送り出し = %d 回, want 0 回", len(mailer.got))
		}
		wantKeysRemoved(t, client, state)
	})
	t.Run("つないだアカウントは行を変えずにログインする", func(t *testing.T) {
		random, _, _ := oidcLoginRandom()
		s, _, _, f := newOIDCCallbackService(t, random)
		id, email, ghID := uuid.New(), uniqueEmail(), uniqueNumber()
		u := verifiedUser(email)
		u.TwoFactor = true
		providers := []providerRow{{ID: uuid.New(), Name: "github", ProviderUserID: ghID, CreatedAt: oldStamp, UpdatedAt: oldStamp}}
		insertStoredUser(t, id, u, []string{"ADMIN", "USER"}, providers, 5)
		f.reply("/github/token", jsonReply(oidcGrantReply))
		f.reply("/github/user", jsonReply(githubUser(ghID)))
		f.reply("/user/emails", jsonReply(githubEmails(uniqueEmail())))
		got := callback(t, s, putOIDCSession(t, s, "github"))
		wantLoggedIn(t, s, got, id, []string{"USER", "ADMIN"}, 5)
		wantRows(t, id, storedRows{
			Found: true, User: u, Roles: []string{"ADMIN", "USER"}, Providers: providers,
			HasVersion: true, Version: 5, VersionAt: oldStamp.Time,
		})
	})
	t.Run("つないだアカウントの確認の済んでいない同じメールアドレスを確認済みにする", func(t *testing.T) {
		random, _, _ := oidcLoginRandom()
		s, _, _, f := newOIDCCallbackService(t, random)
		id, email, sub := uuid.New(), uniqueEmail(), uuid.NewString()
		u := verifiedUser(email)
		u.EmailVerifiedAt = pgtype.Timestamp{}
		providers := []providerRow{{ID: uuid.New(), Name: "google", ProviderUserID: sub, CreatedAt: oldStamp, UpdatedAt: oldStamp}}
		insertStoredUser(t, id, u, []string{"USER"}, providers, 0)
		f.reply("/google/token", jsonReply(oidcGrantReply))
		f.reply("/google/userinfo", jsonReply(googleUserInfo(sub, email)))
		got := callback(t, s, putOIDCSession(t, s, "google"))
		wantLoggedIn(t, s, got, id, []string{"USER"}, 0)
		u.UpdatedAt, u.EmailVerifiedAt = now, now
		wantRows(t, id, storedRows{
			Found: true, User: u, Roles: []string{"USER"}, Providers: providers,
			HasVersion: true, VersionAt: oldStamp.Time,
		})
	})
	t.Run("つないだアカウントの設定待ちの同じメールアドレスを移す", func(t *testing.T) {
		random, _, _ := oidcLoginRandom()
		s, _, _, f := newOIDCCallbackService(t, random)
		id, pending, ghID := uuid.New(), uniqueEmail(), uniqueNumber()
		u := userRow{Username: someText("既存の人"), CreatedAt: oldStamp, UpdatedAt: oldStamp, PendingEmail: someText(pending)}
		providers := []providerRow{{ID: uuid.New(), Name: "github", ProviderUserID: ghID, CreatedAt: oldStamp, UpdatedAt: oldStamp}}
		insertStoredUser(t, id, u, []string{"USER"}, providers, 0)
		f.reply("/github/token", jsonReply(oidcGrantReply))
		f.reply("/github/user", jsonReply(githubUser(ghID)))
		f.reply("/user/emails", jsonReply(githubEmails(pending)))
		got := callback(t, s, putOIDCSession(t, s, "github"))
		wantLoggedIn(t, s, got, id, []string{"USER"}, 0)
		u.Email, u.PendingEmail, u.UpdatedAt, u.EmailVerifiedAt = someText(pending), pgtype.Text{}, now, now
		wantRows(t, id, storedRows{
			Found: true, User: u, Roles: []string{"USER"}, Providers: providers,
			HasVersion: true, VersionAt: oldStamp.Time,
		})
	})
	t.Run("設定待ちのメールアドレスをほかの利用者が使っていれば移さない", func(t *testing.T) {
		random, _, _ := oidcLoginRandom()
		s, _, _, f := newOIDCCallbackService(t, random)
		id, pending, ghID := uuid.New(), uniqueEmail(), uniqueNumber()
		insertStoredUser(t, uuid.New(), verifiedUser(pending), []string{"USER"}, nil, 0)
		u := userRow{Username: someText("既存の人"), CreatedAt: oldStamp, UpdatedAt: oldStamp, PendingEmail: someText(pending)}
		providers := []providerRow{{ID: uuid.New(), Name: "github", ProviderUserID: ghID, CreatedAt: oldStamp, UpdatedAt: oldStamp}}
		insertStoredUser(t, id, u, []string{"USER"}, providers, 0)
		f.reply("/github/token", jsonReply(oidcGrantReply))
		f.reply("/github/user", jsonReply(githubUser(ghID)))
		f.reply("/user/emails", jsonReply(githubEmails(pending)))
		got := callback(t, s, putOIDCSession(t, s, "github"))
		wantLoggedIn(t, s, got, id, []string{"USER"}, 0)
		wantRows(t, id, storedRows{
			Found: true, User: u, Roles: []string{"USER"}, Providers: providers,
			HasVersion: true, VersionAt: oldStamp.Time,
		})
	})
	t.Run("大文字と小文字だけが違う名前の連携があれば足さない", func(t *testing.T) {
		random, _, _ := oidcLoginRandom()
		s, _, _, f := newOIDCCallbackService(t, random)
		id, email := uuid.New(), uniqueEmail()
		u := verifiedUser(email)
		providers := []providerRow{{ID: uuid.New(), Name: "Google", ProviderUserID: "old-" + uuid.NewString(), CreatedAt: oldStamp, UpdatedAt: oldStamp}}
		insertStoredUser(t, id, u, []string{"USER"}, providers, 0)
		f.reply("/google/token", jsonReply(oidcGrantReply))
		f.reply("/google/userinfo", jsonReply(googleUserInfo(uuid.NewString(), email)))
		got := callback(t, s, putOIDCSession(t, s, "google"))
		wantLoggedIn(t, s, got, id, []string{"USER"}, 0)
		wantRows(t, id, storedRows{
			Found: true, User: u, Roles: []string{"USER"}, Providers: providers,
			HasVersion: true, VersionAt: oldStamp.Time,
		})
	})
	t.Run("同じ連携の利用者が2人いれば断る", func(t *testing.T) {
		random, _, _ := oidcLoginRandom()
		s, client, _, f := newOIDCCallbackService(t, random)
		sub := uuid.NewString()
		for range 2 {
			providers := []providerRow{{ID: uuid.New(), Name: "google", ProviderUserID: sub, CreatedAt: oldStamp, UpdatedAt: oldStamp}}
			insertStoredUser(t, uuid.New(), verifiedUser(uniqueEmail()), []string{"USER"}, providers, 0)
		}
		f.reply("/google/token", jsonReply(oidcGrantReply))
		f.reply("/google/userinfo", jsonReply(googleUserInfo(sub, uniqueEmail())))
		state := putOIDCSession(t, s, "google")
		wantFailure(t, callback(t, s, state), loginFailedURL(t))
		wantKeysRemoved(t, client, state)
	})
}

// TestHandleOIDCCallback_UnverifiedEmail は、Google か GitHub の利用者の ID でつないだアカウントが無く、同じメールアドレスの
// アカウントの確認が済んでいないとき、Java 版と同じく、つながずに画面の /login?error=unverified_email に移すことを確かめる
// (要件1.3)。
func TestHandleOIDCCallback_UnverifiedEmail(t *testing.T) {
	for _, provider := range []string{"google", "github"} {
		t.Run(provider, func(t *testing.T) {
			random, _, _ := oidcLoginRandom()
			s, client, mailer, f := newOIDCCallbackService(t, random)
			id, email := uuid.New(), uniqueEmail()
			u := userRow{
				Email: someText(email), Password: someText(javaBcryptSample), Username: someText("未確認の人"),
				CreatedAt: oldStamp, UpdatedAt: oldStamp,
			}
			insertStoredUser(t, id, u, []string{"USER"}, nil, 0)
			f.reply("/"+provider+"/token", jsonReply(oidcGrantReply))
			f.reply("/google/userinfo", jsonReply(googleUserInfo(uuid.NewString(), email)))
			f.reply("/github/user", jsonReply(githubUser(uniqueNumber())))
			f.reply("/user/emails", jsonReply(githubEmails(email)))
			state := putOIDCSession(t, s, provider)
			wantFailure(t, callback(t, s, state), unverifiedURL(t))
			wantRows(t, id, storedRows{
				Found: true, User: u, Roles: []string{"USER"}, Providers: []providerRow{},
				HasVersion: true, VersionAt: oldStamp.Time,
			})
			if len(mailer.got) != 0 {
				t.Errorf("メールの送り出し = %d 回, want 0 回", len(mailer.got))
			}
			wantKeysRemoved(t, client, state)
		})
	}
}

// TestHandleOIDCCallback_Denied は、Google か GitHub がログインを断ったとき、コードを交換できないとき、利用者の情報を
// 読めないときに、Java 版の OidcCallbackController と同じ文言で画面の /login に移し、state の3つの記録を消すことを
// 確かめる(要件1.3)。利用者の情報を読めないときだけ、文言を「ユーザー情報の取得に失敗しました。…」にする。
func TestHandleOIDCCallback_Denied(t *testing.T) {
	t.Run("error の項目があれば交換しない", func(t *testing.T) {
		for _, errParam := range []string{"access_denied", ""} {
			random, _, _ := oidcLoginRandom()
			s, client, _, f := newOIDCCallbackService(t, random)
			f.reply("/google/token", jsonReply(oidcGrantReply))
			state := putOIDCSession(t, s, "google")
			code := oidcCode
			got := s.HandleOIDCCallback(t.Context(), &code, &state, &errParam, testCallbackURI)
			wantFailure(t, got, loginFailedURL(t))
			wantKeysRemoved(t, client, state)
			if n := len(f.received("/google/token")); n != 0 {
				t.Errorf("error=%q でコードの交換 = %d 回, want 0 回", errParam, n)
			}
		}
	})
	cases := []struct {
		name, provider string
		grant, info    fakeReply
		want           func(t *testing.T) string
	}{
		{"交換が 400", "google", fakeReply{400, "application/json", `{"error":"invalid_grant"}`}, jsonReply(""), loginFailedURL},
		{"交換が 500 で本文に error", "github", fakeReply{500, "application/json", `{"error":"server_error","access_token":"x"}`}, jsonReply(""), loginFailedURL},
		{"交換の応答の error", "google", jsonReply(`{"error":"invalid_grant","access_token":"x"}`), jsonReply(""), loginFailedURL},
		{"交換の応答が空", "google", jsonReply(""), jsonReply(""), loginFailedURL},
		{"交換の応答が null", "google", jsonReply("null"), jsonReply(""), loginFailedURL},
		{"交換の応答が並び", "google", jsonReply("[]"), jsonReply(""), loginFailedURL},
		{"交換の応答の文字列の項目がオブジェクト", "google", jsonReply(`{"access_token":{"a":1}}`), jsonReply(""), loginFailedURL},
		{"交換の応答の expires_in が真偽", "google", jsonReply(`{"access_token":"x","expires_in":true}`), jsonReply(""), loginFailedURL},
		{"交換の応答の expires_in が int の範囲の外", "google", jsonReply(`{"access_token":"x","expires_in":2147483648}`), jsonReply(""), loginFailedURL},
		{"交換の応答の expires_in が小数の文字列", "google", jsonReply(`{"access_token":"x","expires_in":"1.5"}`), jsonReply(""), loginFailedURL},
		{"交換の応答が JSON の種類でない", "google", fakeReply{200, "text/plain", oidcGrantReply}, jsonReply(""), loginFailedURL},
		{"交換の応答に Content-Type が無い", "google", fakeReply{200, "", oidcGrantReply}, jsonReply(""), loginFailedURL},
		{"利用者の情報が 401 で sub が無い", "google", jsonReply(oidcGrantReply), fakeReply{401, "application/json", `{}`}, loginFailedURL},
		{"利用者の情報が空", "github", jsonReply(oidcGrantReply), jsonReply(""), userInfoFailedURL},
		{"利用者の情報が null", "google", jsonReply(oidcGrantReply), jsonReply("null"), userInfoFailedURL},
		{"利用者の情報が並び", "github", jsonReply(oidcGrantReply), jsonReply(`[{"id":1}]`), userInfoFailedURL},
		{"利用者の情報が JSON の種類でない", "google", jsonReply(oidcGrantReply), fakeReply{200, "text/html", `{"sub":"s"}`}, userInfoFailedURL},
		{"Google の email_verified が文字列", "google", jsonReply(oidcGrantReply), jsonReply(`{"sub":"s","email":"a@example.com","email_verified":"true","name":"n"}`), userInfoFailedURL},
		{"Google の email が数", "google", jsonReply(oidcGrantReply), jsonReply(`{"sub":"s","email":1,"email_verified":false,"name":"n"}`), userInfoFailedURL},
		{"Google の sub が数", "google", jsonReply(oidcGrantReply), jsonReply(`{"sub":1,"name":"n"}`), userInfoFailedURL},
		{"Google の name が真偽", "google", jsonReply(oidcGrantReply), jsonReply(`{"sub":"s","name":true}`), userInfoFailedURL},
		{"GitHub の login が数", "github", jsonReply(oidcGrantReply), jsonReply(`{"id":1,"login":2}`), userInfoFailedURL},
		{"GitHub の id が小数", "github", jsonReply(oidcGrantReply), jsonReply(`{"id":1.5,"login":"a"}`), userInfoFailedURL},
		{"GitHub の id がオブジェクト", "github", jsonReply(oidcGrantReply), jsonReply(`{"id":{},"login":"a"}`), userInfoFailedURL},
		{"対象の外の provider の記録", "twitter", jsonReply(oidcGrantReply), jsonReply(""), loginFailedURL},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			random, _, _ := oidcLoginRandom()
			s, client, mailer, f := newOIDCCallbackService(t, random)
			f.reply("/"+c.provider+"/token", c.grant)
			f.reply("/google/userinfo", c.info)
			f.reply("/github/user", c.info)
			f.reply("/user/emails", jsonReply(githubEmails(uniqueEmail())))
			state := putOIDCSession(t, s, c.provider)
			wantFailure(t, callback(t, s, state), c.want(t))
			wantKeysRemoved(t, client, state)
			if len(mailer.got) != 0 {
				t.Errorf("メールの送り出し = %d 回, want 0 回", len(mailer.got))
			}
		})
	}
}

// TestHandleOIDCCallback_ReadsResponsesLikeJava は、Java 版の RestClient と Jackson の設定と同じく、Google と GitHub の
// 応答を、状態の番号によらず読み、先頭の JSON の値のあとを読まず、expires_in を OidcTokenResponse の Integer の規則で
// 確かめるだけにして、ログインを続けることを確かめる(要件1.3)。
func TestHandleOIDCCallback_ReadsResponsesLikeJava(t *testing.T) {
	cases := []struct {
		name        string
		grant, info func(sub, email string) fakeReply
	}{
		{"交換が 500 でも本文を読む", func(string, string) fakeReply {
			return fakeReply{500, "application/json", oidcGrantReply}
		}, nil},
		{"利用者の情報が 401 でも本文を読む", nil, func(sub, email string) fakeReply {
			return fakeReply{401, "application/json", googleUserInfo(sub, email)}
		}},
		{"交換の応答のあとの余計な値を読まない", func(string, string) fakeReply { return jsonReply(oidcGrantReply + ` 1 }`) }, nil},
		{"利用者の情報のあとの余計な値を読まない", nil, func(sub, email string) fakeReply {
			return jsonReply(googleUserInfo(sub, email) + `[`)
		}},
		{"expires_in が無い", func(string, string) fakeReply { return jsonReply(`{"access_token":"` + oidcGrant + `"}`) }, nil},
		{"expires_in が null", func(string, string) fakeReply {
			return jsonReply(`{"access_token":"` + oidcGrant + `","expires_in":null}`)
		}, nil},
		{"expires_in が文字列の整数", func(string, string) fakeReply {
			return jsonReply(`{"access_token":"` + oidcGrant + `","expires_in":" -3599 "}`)
		}, nil},
		{"expires_in が小数", func(string, string) fakeReply {
			return jsonReply(`{"access_token":"` + oidcGrant + `","expires_in":3599.9}`)
		}, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			random, _, uid := oidcLoginRandom()
			s, client, _, f := newOIDCCallbackService(t, random)
			email, sub := uniqueEmail(), uuid.NewString()
			grant, info := jsonReply(oidcGrantReply), jsonReply(googleUserInfo(sub, email))
			if c.grant != nil {
				grant = c.grant(sub, email)
			}
			if c.info != nil {
				info = c.info(sub, email)
			}
			f.reply("/google/token", grant)
			f.reply("/google/userinfo", info)
			state := putOIDCSession(t, s, "google")
			got := callback(t, s, state)
			wantLoggedIn(t, s, got, uid, []string{"USER"}, 0)
			wantUserInfoRequest(t, f, "/google/userinfo", false)
			if rows := readStoredRows(t, uid); !rows.Found || len(rows.Providers) != 1 || rows.Providers[0].ProviderUserID != sub {
				t.Errorf("作った利用者の連携の行 = %+v, want sub %s の google の1行", rows.Providers, sub)
			}
			wantKeysRemoved(t, client, state)
		})
	}
}

// TestHandleOIDCCallback_ErrorMessageURLEncoderEscape は、移る先の URL に入れる文言を、url.QueryEscape ではなく、
// Java の URLEncoder.encode と同じ規則でエスケープすることを確かめる(要件1.3)。英数字と . - * _ を残し、空白を + にし、
// ほかは UTF-8 のバイトごとに大文字の %XX にする。url.QueryEscape と違い、* を残し、~ をエスケープする。
func TestHandleOIDCCallback_ErrorMessageURLEncoderEscape(t *testing.T) {
	cases := []struct{ in, want string }{
		{"a b*~", "a+b*%7E"},
		{"-._*AZaz09", "-._*AZaz09"},
		{"!'()", "%21%27%28%29"},
		{"/?&=+%#", "%2F%3F%26%3D%2B%25%23"},
		{"é", "%C3%A9"},
		{"認証", "%E8%AA%8D%E8%A8%BC"},
		{"", ""},
	}
	for _, c := range cases {
		if got := javaURLEncode(c.in); got != c.want {
			t.Errorf("javaURLEncode(%q) = %q, want %q", c.in, got, c.want)
		}
	}
	random, _, _ := oidcLoginRandom()
	s, _, _, _ := newOIDCCallbackService(t, random)
	state, code, errParam := uuid.NewString(), oidcCode, "access_denied"
	got := s.HandleOIDCCallback(t.Context(), &code, &state, &errParam, testCallbackURI)
	want := s.deps.App.FrontendBaseURL + "/login?error=" +
		"%E8%AA%8D%E8%A8%BC%E3%81%AB%E5%A4%B1%E6%95%97%E3%81%97%E3%81%BE%E3%81%97%E3%81%9F%E3%80%82" +
		"%E3%81%97%E3%81%B0%E3%82%89%E3%81%8F%E6%99%82%E9%96%93%E3%82%92%E7%BD%AE%E3%81%84%E3%81%A6%E3%81%8B%E3%82%89" +
		"%E5%86%8D%E5%BA%A6%E3%81%8A%E8%A9%A6%E3%81%97%E3%81%8F%E3%81%A0%E3%81%95%E3%81%84%E3%80%82"
	if got.Location != want {
		t.Errorf("移る先 =\n%s\nwant\n%s", got.Location, want)
	}
	if want != loginFailedURL(t) {
		t.Errorf("テストの期待の URL が url.QueryEscape の結果と違う: %s", loginFailedURL(t))
	}
}

// TestHandleOIDCCallback_GitHubPrimaryVerifiedOnly は、Java 版の GithubOidcProvider と同じく、GitHub のメールアドレスの
// 一覧のうち、先頭から見て最初の、主で確認済みのメールアドレスだけを使い、一覧を読めないときはメールアドレスの無い
// 利用者としてログインを続けることを確かめる(要件3.7)。
func TestHandleOIDCCallback_GitHubPrimaryVerifiedOnly(t *testing.T) {
	now := javaWallClock(completionNow)
	cases := []struct {
		name  string
		reply func(email string) fakeReply
		use   bool
	}{
		{"主で確認済み", func(e string) fakeReply { return jsonReply(githubEmails(e)) }, true},
		{"主でない確認済みは使わない", func(e string) fakeReply {
			return jsonReply(`[{"email":"` + e + `","primary":false,"verified":true}]`)
		}, false},
		{"確認の済んでいない主は使わない", func(e string) fakeReply {
			return jsonReply(`[{"email":"` + e + `","primary":true,"verified":false}]`)
		}, false},
		{"真偽でない primary は使わない", func(e string) fakeReply {
			return jsonReply(`[{"email":"` + e + `","primary":"true","verified":true}]`)
		}, false},
		{"最初に当たったものを使う", func(e string) fakeReply {
			return jsonReply(`[{"email":"` + e + `","primary":true,"verified":true},{"email":"x-` + e + `","primary":true,"verified":true}]`)
		}, true},
		{"当たる前の null の要素", func(e string) fakeReply {
			return jsonReply(`[null,{"email":"` + e + `","primary":true,"verified":true}]`)
		}, false},
		{"当たったあとの null の要素", func(e string) fakeReply {
			return jsonReply(`[{"email":"` + e + `","primary":true,"verified":true},null]`)
		}, true},
		{"オブジェクトでない要素", func(e string) fakeReply {
			return jsonReply(`[{"email":"` + e + `","primary":true,"verified":true},"x"]`)
		}, false},
		{"当たった要素の email が null", func(e string) fakeReply {
			return jsonReply(`[{"email":null,"primary":true,"verified":true},{"email":"` + e + `","primary":true,"verified":true}]`)
		}, false},
		{"当たった要素の email が数", func(string) fakeReply {
			return jsonReply(`[{"email":1,"primary":true,"verified":true}]`)
		}, false},
		{"一覧が 403 でも読む", func(e string) fakeReply { return fakeReply{403, "application/json", githubEmails(e)} }, true},
		{"一覧が空", func(string) fakeReply { return jsonReply("") }, false},
		{"一覧が null", func(string) fakeReply { return jsonReply("null") }, false},
		{"一覧がオブジェクト", func(e string) fakeReply {
			return jsonReply(`{"email":"` + e + `","primary":true,"verified":true}`)
		}, false},
		{"一覧のあとの余計な値を読まない", func(e string) fakeReply { return jsonReply(githubEmails(e) + " []") }, true},
		{"一覧は JSON の種類でなくても読む", func(e string) fakeReply { return fakeReply{200, "text/plain", githubEmails(e)} }, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			random, pid, uid := oidcLoginRandom()
			s, client, mailer, f := newOIDCCallbackService(t, random)
			email, ghID := uniqueEmail(), uniqueNumber()
			f.reply("/github/token", jsonReply(oidcGrantReply))
			f.reply("/github/user", jsonReply(githubUser(ghID)))
			f.reply("/user/emails", c.reply(email))
			state := putOIDCSession(t, s, "github")
			got := callback(t, s, state)
			wantLoggedIn(t, s, got, uid, []string{"USER"}, 0)
			var used *string
			var verifiedAt pgtype.Timestamp
			if c.use {
				used, verifiedAt = strPtr(email), now
			}
			wantRows(t, uid, storedRows{
				Found: true,
				User: userRow{
					Email: someTextPtr(used), Username: someText(oidcName),
					CreatedAt: now, UpdatedAt: now, EmailVerifiedAt: verifiedAt,
				},
				Roles:      []string{"USER"},
				Providers:  []providerRow{{ID: pid, Name: "github", ProviderUserID: ghID, CreatedAt: now, UpdatedAt: now}},
				HasVersion: true,
				VersionAt:  now.Time,
			})
			if c.use {
				wantRegisteredMail(t, s, mailer, email)
			} else if len(mailer.got) != 0 {
				t.Errorf("メールの送り出し = %d 回, want 0 回", len(mailer.got))
			}
			wantKeysRemoved(t, client, state)
		})
	}
	t.Run("GitHub の id の書き方", func(t *testing.T) {
		for _, c := range []struct{ raw, want string }{
			{`"abc"`, "abc"},
			{`-0`, "0"},
			{`true`, "true"},
			{`null`, "null"},
			{`123456789012345678901234567890`, "123456789012345678901234567890"},
		} {
			random, pid, uid := oidcLoginRandom()
			s, _, _, f := newOIDCCallbackService(t, random)
			f.reply("/github/token", jsonReply(oidcGrantReply))
			f.reply("/github/user", jsonReply(`{"id":`+c.raw+`,"login":"`+oidcName+`"}`))
			f.reply("/user/emails", jsonReply("[]"))
			// 同じ ID の連携の行が前に流したテストで残っていても新しい利用者を作るよう、先に消す。
			if _, err := testPool.Exec(t.Context(), `DELETE FROM user_auth_providers WHERE provider_name = 'github' AND provider_user_id = $1`, c.want); err != nil {
				t.Fatal(err)
			}
			got := callback(t, s, putOIDCSession(t, s, "github"))
			wantLoggedIn(t, s, got, uid, []string{"USER"}, 0)
			rows := readStoredRows(t, uid)
			wantProviders := []providerRow{{ID: pid, Name: "github", ProviderUserID: c.want, CreatedAt: now, UpdatedAt: now}}
			if !reflect.DeepEqual(rows.Providers, wantProviders) {
				t.Errorf("id %s の連携の行 = %+v, want %+v", c.raw, rows.Providers, wantProviders)
			}
		}
	})
}

// TestHandleOIDCCallback_MissingState は、code か state が無いとき、state の記録が無いとき、記録の値が JSON の文字列で
// ないとき、Redis を読めないときに、Java 版の HandleOidcCallbackUseCase と同じく、コードを交換せずに失敗にし、state が
// あれば3つの記録を消すことを確かめる(要件3.7)。
func TestHandleOIDCCallback_MissingState(t *testing.T) {
	type setup func(t *testing.T, s *Service, client redis.UniversalClient) (code, state *string)
	cases := []struct {
		name     string
		setup    setup
		keysGone bool
	}{
		{"code が無い", func(t *testing.T, s *Service, _ redis.UniversalClient) (*string, *string) {
			return nil, strPtr(putOIDCSession(t, s, "google"))
		}, true},
		{"state が無い", func(*testing.T, *Service, redis.UniversalClient) (*string, *string) {
			return strPtr(oidcCode), nil
		}, false},
		{"state の記録が無い", func(t *testing.T, s *Service, client redis.UniversalClient) (*string, *string) {
			state := putOIDCSession(t, s, "google")
			if err := client.Del(t.Context(), oidcStateKeyPrefix+state).Err(); err != nil {
				t.Fatal(err)
			}
			return strPtr(oidcCode), &state
		}, true},
		{"provider の記録が無い", func(t *testing.T, s *Service, client redis.UniversalClient) (*string, *string) {
			state := putOIDCSession(t, s, "google")
			if err := client.Del(t.Context(), oidcProviderKeyPrefix+state).Err(); err != nil {
				t.Fatal(err)
			}
			return strPtr(oidcCode), &state
		}, true},
		{"code_verifier の記録が数", func(t *testing.T, s *Service, client redis.UniversalClient) (*string, *string) {
			state := putOIDCSession(t, s, "google")
			if err := client.Set(t.Context(), oidcCodeVerifierKeyPrefix+state, "1", time.Minute).Err(); err != nil {
				t.Fatal(err)
			}
			return strPtr(oidcCode), &state
		}, true},
		{"空の state", func(t *testing.T, _ *Service, client redis.UniversalClient) (*string, *string) {
			if err := client.Set(t.Context(), oidcStateKeyPrefix, `""`, time.Minute).Err(); err != nil {
				t.Fatal(err)
			}
			if err := client.Set(t.Context(), oidcProviderKeyPrefix, `"google"`, time.Minute).Err(); err != nil {
				t.Fatal(err)
			}
			return strPtr(oidcCode), strPtr("")
		}, true},
		{"Redis を読めない", func(t *testing.T, s *Service, client redis.UniversalClient) (*string, *string) {
			state := putOIDCSession(t, s, "google")
			_ = client.Close()
			return strPtr(oidcCode), &state
		}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			random, _, _ := oidcLoginRandom()
			s, client, _, f := newOIDCCallbackService(t, random)
			f.reply("/google/token", jsonReply(oidcGrantReply))
			f.reply("/google/userinfo", jsonReply(googleUserInfo(uuid.NewString(), uniqueEmail())))
			code, state := c.setup(t, s, client)
			got := s.HandleOIDCCallback(t.Context(), code, state, nil, testCallbackURI)
			wantFailure(t, got, loginFailedURL(t))
			if n := len(f.received("/google/token")); n != 0 {
				t.Errorf("コードの交換 = %d 回, want 0 回", n)
			}
			if c.keysGone {
				wantKeysRemoved(t, client, *state)
			}
		})
	}
}
