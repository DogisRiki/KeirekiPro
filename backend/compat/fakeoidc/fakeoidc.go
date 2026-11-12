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
// 比べる検査は、/_compat/ の下の口で、クライアントの値と利用者の値を登録し、ログインの開始を断らせ、
// 利用者の値と断る残りの回数を初めの状態に戻す。
//
// 起動のときに証明書と鍵のファイルの場所を渡されたときだけ、ネットワークの別名 api.github.com として、
// ポート 443 で TLS を受け、/user/emails の口だけに答える。Java 版と Go 版は、GitHub のメールアドレスを
// 設定の URL ではなく決まった https://api.github.com/user/emails から読むためである。
package fakeoidc

import (
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"sync"
	"time"
)

const (
	// Port は、このサーバが受けるポートである。
	Port = "8080"
	// TLSPort は、api.github.com として TLS を受けるポートである。
	TLSPort = "443"

	// CertFileEnv は、api.github.com の証明書の PEM のファイルの場所を渡す環境変数の名前である。
	CertFileEnv = "FAKEOIDC_TLS_CERT_FILE"
	// KeyFileEnv は、api.github.com の証明書の鍵の PEM のファイルの場所を渡す環境変数の名前である。
	KeyFileEnv = "FAKEOIDC_TLS_KEY_FILE"

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
	// denies は、提供元ごとの断る残りの回数である。
	denies map[string]int
}

// NewServer は、クライアントと利用者を登録していない Server を作る。
func NewServer() *Server {
	s := &Server{clients: map[string]Client{}, codes: map[string]grant{}, tokens: map[string]grant{}, denies: map[string]int{}}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /_compat/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("PUT /_compat/clients/{provider}", s.putClient)
	mux.HandleFunc("PUT /_compat/users/google", s.putGoogleUser)
	mux.HandleFunc("PUT /_compat/users/github", s.putGitHubUser)
	mux.HandleFunc("PUT /_compat/deny/{provider}", s.putDeny)
	mux.HandleFunc("POST /_compat/reset", s.postReset)
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

// TLSServer は、証明書 certFile と鍵 keyFile で、api.github.com としてポート 443 の TLS を受けるサーバを作る。
// サーバは /user/emails の口だけに答え、ほかの口を 501 で断る。
// certFile と keyFile がどちらも空のときは、TLS を受けないので、nil を返す。
// 片方だけが空のときと、ファイルを読めないときは、誤りを返す。空の場所のファイルは読めないので、片方だけが空のときも読む誤りになる。
func (s *Server) TLSServer(certFile, keyFile string) (*http.Server, error) {
	if certFile == "" && keyFile == "" {
		return nil, nil
	}
	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return nil, fmt.Errorf("TLS の証明書と鍵を読めません: %w", err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /user/emails", s.githubEmails)
	mux.HandleFunc("/", s.notImplemented)
	return &http.Server{
		Addr:              net.JoinHostPort("", TLSPort),
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		TLSConfig:         &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{cert}},
	}, nil
}
