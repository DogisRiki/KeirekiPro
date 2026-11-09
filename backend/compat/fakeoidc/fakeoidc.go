//go:build compat

// Package fakeoidc は、比べる検査で Java 版と Go 版がつなぐ、Google と GitHub のログインの代わりである。
//
// 1つの HTTP のサーバで、本物と同じパスの次の口を受ける。
//   - Google: 認可 /o/oauth2/v2/auth、token /token、userinfo /v1/userinfo
//   - GitHub: 認可 /login/oauth/authorize、token /login/oauth/access_token、/user、/user/emails
//
// 認可の口は、利用者に画面を見せずに、すぐに認可のコードを付けて redirect_uri へ転送する。
// token の口は、クライアントの値と redirect_uri と PKCE の code_verifier を確かめてから、アクセストークンを返す。
// userinfo と /user と /user/emails の口は、比べる検査が筋書きの始めに登録した利用者の値を返す。
//
// 比べる検査は、/_compat/ の下の口で、クライアントの値と利用者の値を登録する。
package fakeoidc

import (
	"net/http"
	"net/url"
	"sync"
)

const (
	// Port は、このサーバが受けるポートである。
	Port = "8080"

	// Google は、Google の提供元の名前である。
	Google = "google"
	// GitHub は、GitHub の提供元の名前である。
	GitHub = "github"
)

// Client は、提供元に登録するクライアントの値である。比べる検査は、筋書きの前に、同じ値を
// fakeoidc と fakeaws の秘密の値の両方に登録する。
type Client struct {
	ID     string
	Secret string
	// RedirectURIs は、認可の口が転送してよい redirect_uri の一覧である。本物の提供元と同じく、一覧に無い転送先は断る。
	RedirectURIs []string
}

// Form は、/_compat/clients/{provider} の口に送る本文の形にした値を返す。
// OAuth の token の口と同じく、URL の形で符号化した本文で送る。
func (c Client) Form() url.Values {
	return url.Values{"client_id": {c.ID}, "client_secret": {c.Secret}, "redirect_uri": c.RedirectURIs}
}

// GoogleUser は、Google の userinfo が返す利用者の値である。
type GoogleUser struct {
	Sub           string `json:"sub"`
	Name          string `json:"name"`
	Email         string `json:"email"`
	EmailVerified bool   `json:"email_verified"`
}

// GitHubEmail は、GitHub の /user/emails が返すメールアドレスの1件である。
type GitHubEmail struct {
	Email    string `json:"email"`
	Primary  bool   `json:"primary"`
	Verified bool   `json:"verified"`
}

// GitHubUser は、GitHub の /user と /user/emails が返す利用者の値である。
type GitHubUser struct {
	ID     int64         `json:"id"`
	Login  string        `json:"login"`
	Emails []GitHubEmail `json:"emails"`
}

// grant は、認可の口が出したコードか、token の口が出したアクセストークンが指すものである。
type grant struct {
	provider      string
	redirectURI   string
	codeChallenge string
	google        GoogleUser
	github        GitHubUser
}

// Server は、ログインの代わりの HTTP のサーバの処理である。
type Server struct {
	mux *http.ServeMux

	mu         sync.Mutex
	clients    map[string]Client
	googleUser *GoogleUser
	githubUser *GitHubUser
	codes      map[string]grant
	tokens     map[string]grant
	issued     int
}

// NewServer は、クライアントと利用者を登録していない Server を作る。
func NewServer() *Server {
	s := &Server{clients: map[string]Client{}, codes: map[string]grant{}, tokens: map[string]grant{}}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /_compat/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("PUT /_compat/clients/{provider}", s.putClient)
	mux.HandleFunc("PUT /_compat/users/google", s.putGoogleUser)
	mux.HandleFunc("PUT /_compat/users/github", s.putGitHubUser)
	mux.HandleFunc("GET /o/oauth2/v2/auth", s.authorize(Google))
	mux.HandleFunc("POST /token", s.token(Google))
	mux.HandleFunc("GET /v1/userinfo", s.googleUserInfo)
	mux.HandleFunc("GET /login/oauth/authorize", s.authorize(GitHub))
	mux.HandleFunc("POST /login/oauth/access_token", s.token(GitHub))
	mux.HandleFunc("GET /user", s.githubUserInfo)
	mux.HandleFunc("GET /user/emails", s.githubEmails)
	mux.HandleFunc("/", s.notImplemented)
	s.mux = mux
	return s
}

// ServeHTTP は、要求を口ごとの処理に振り分ける。
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mux.ServeHTTP(w, r)
}

// SetClient は、提供元 provider のクライアントの値を登録する。前に登録した値と置き換える。
func (s *Server) SetClient(provider string, c Client) {
	s.mu.Lock()
	defer s.mu.Unlock()
	c.RedirectURIs = append([]string{}, c.RedirectURIs...)
	s.clients[provider] = c
}

// clientOf は、提供元 provider に登録したクライアントの値を返す。
func (s *Server) clientOf(provider string) (Client, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	c, ok := s.clients[provider]
	return c, ok
}

// SetGoogleUser は、Google でログインする利用者を登録する。前に登録した利用者と置き換える。
func (s *Server) SetGoogleUser(u GoogleUser) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.googleUser = &u
}

// SetGitHubUser は、GitHub でログインする利用者を登録する。前に登録した利用者と置き換える。
func (s *Server) SetGitHubUser(u GitHubUser) {
	s.mu.Lock()
	defer s.mu.Unlock()
	u.Emails = append([]GitHubEmail{}, u.Emails...)
	s.githubUser = &u
}
