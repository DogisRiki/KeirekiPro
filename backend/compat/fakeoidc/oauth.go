//go:build compat

package fakeoidc

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
)

// maxBodySize は、受ける本文の大きさの上限である。
const maxBodySize = 64 << 10

// authorize は、提供元の認可の口を作る。利用者に画面を見せずに、認可のコードを付けて redirect_uri へ転送する。
func (s *Server) authorize(provider string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		client, ok := s.clientOf(provider)
		if !ok || q.Get("client_id") != client.ID {
			http.Error(w, "client_id が登録したクライアントと違います", http.StatusBadRequest)
			return
		}
		// 本物の提供元と同じく、登録した転送先の一覧に無い redirect_uri へは転送しない。
		// Java 版と Go 版はどちらも redirect_uri を送るので、省いた要求も断る。
		redirect, ok := registeredRedirect(client, q.Get("redirect_uri"))
		if !ok {
			http.Error(w, "redirect_uri が登録した転送先にありません", http.StatusBadRequest)
			return
		}
		if provider == Google && q.Get("response_type") != "code" {
			http.Error(w, "response_type が code ではありません", http.StatusBadRequest)
			return
		}
		challenge := q.Get("code_challenge")
		if challenge != "" && q.Get("code_challenge_method") != "S256" {
			http.Error(w, "code_challenge_method が S256 ではありません", http.StatusBadRequest)
			return
		}
		if s.takeDeny(provider) {
			writeDenied(w, redirect, q.Get("state"))
			return
		}

		s.mu.Lock()
		g := grant{provider: provider, redirectURI: redirect.String(), codeChallenge: challenge}
		registered := true
		switch {
		case provider == Google && s.googleUser != nil:
			g.google = *s.googleUser
		case provider == GitHub && s.githubUser != nil:
			g.github = *s.githubUser
		default:
			registered = false
		}
		code := ""
		if registered {
			s.issued++
			code = fmt.Sprintf("fakeoidc-code-%d", s.issued)
			s.codes[code] = g
		}
		s.mu.Unlock()
		if !registered {
			http.Error(w, "比べる検査が "+provider+" の利用者を登録していません", http.StatusConflict)
			return
		}

		params := redirect.Query()
		params.Set("code", code)
		if state := q.Get("state"); state != "" {
			params.Set("state", state)
		}
		redirect.RawQuery = params.Encode()
		w.Header().Set("Location", redirect.String())
		w.WriteHeader(http.StatusFound)
	}
}

// token は、提供元の token の口を作る。認可のコードを1回だけ、アクセストークンと引き換える。
func (s *Server) token(provider string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, maxBodySize)
		if err := r.ParseForm(); err != nil {
			writeTokenError(w, r, provider, http.StatusBadRequest, "invalid_request", "本文を読めません")
			return
		}
		client, registered := s.clientOf(provider)
		if !registered || !validClient(r, client) {
			writeTokenError(w, r, provider, http.StatusUnauthorized, "invalid_client", "クライアントの値が違います")
			return
		}
		grantType := r.PostForm.Get("grant_type")
		if grantType != "authorization_code" && (provider == Google || grantType != "") {
			writeTokenError(w, r, provider, http.StatusBadRequest, "unsupported_grant_type", "grant_type が authorization_code ではありません")
			return
		}

		code := r.PostForm.Get("code")
		s.mu.Lock()
		g, ok := s.codes[code]
		delete(s.codes, code)
		s.mu.Unlock()
		switch {
		case !ok || g.provider != provider:
			writeTokenError(w, r, provider, http.StatusBadRequest, "invalid_grant", "認可のコードが無いか、使い済みです")
			return
		case r.PostForm.Get("redirect_uri") != g.redirectURI && (provider == Google || r.PostForm.Has("redirect_uri")):
			writeTokenError(w, r, provider, http.StatusBadRequest, "invalid_grant", "redirect_uri が認可のときと違います")
			return
		case g.codeChallenge != "" && !verifierMatches(r.PostForm.Get("code_verifier"), g.codeChallenge):
			writeTokenError(w, r, provider, http.StatusBadRequest, "invalid_grant", "code_verifier が code_challenge と合いません")
			return
		}

		s.mu.Lock()
		s.issued++
		accessToken := fmt.Sprintf("fakeoidc-token-%d", s.issued)
		s.tokens[accessToken] = g
		s.mu.Unlock()

		if provider == Google {
			writeJSON(w, r, http.StatusOK, map[string]any{"access_token": accessToken, "token_type": "Bearer", "expires_in": 3599})
			return
		}
		writeGitHubToken(w, r, http.StatusOK, url.Values{"access_token": {accessToken}, "token_type": {"bearer"}, "scope": {"read:user,user:email"}})
	}
}

// validClient は、クライアントの値が、本文か Basic 認証のどちらかで正しく渡されたかを返す。
// Basic 認証の値は、RFC 6749 の 2.3.1 のとおり、URL の形で符号化されたものとして読む。
func validClient(r *http.Request, want Client) bool {
	id, secret := r.PostForm.Get("client_id"), r.PostForm.Get("client_secret")
	if user, pass, ok := r.BasicAuth(); ok {
		var errUser, errPass error
		id, errUser = url.QueryUnescape(user)
		secret, errPass = url.QueryUnescape(pass)
		if errUser != nil || errPass != nil {
			return false
		}
	}
	return subtle.ConstantTimeCompare([]byte(id), []byte(want.ID)) == 1 &&
		subtle.ConstantTimeCompare([]byte(secret), []byte(want.Secret)) == 1
}

// registeredRedirect は、redirect_uri がクライアントに登録した転送先の1つと同じなら、登録した転送先を返す。
func registeredRedirect(c Client, redirectURI string) (*url.URL, bool) {
	for _, allowed := range c.RedirectURIs {
		if allowed != redirectURI {
			continue
		}
		u, err := url.Parse(allowed)
		return u, err == nil && u.IsAbs()
	}
	return nil, false
}

// verifierMatches は、PKCE の code_verifier の SHA-256 が、認可のときの code_challenge と合うかを返す。
func verifierMatches(verifier, challenge string) bool {
	if verifier == "" {
		return false
	}
	sum := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(sum[:]) == challenge
}

// githubErrorCodes は、OAuth の誤りの名前を、GitHub が token の口で返す誤りの名前に置き換える表である。
// https://docs.github.com/en/apps/oauth-apps/maintaining-oauth-apps/troubleshooting-oauth-app-access-token-request-errors
var githubErrorCodes = map[string]string{
	"invalid_client": "incorrect_client_credentials",
	"invalid_grant":  "bad_verification_code",
}

// writeTokenError は、token の口の誤りを返す。
// Google には 400 か 401 で返す。GitHub の文書は、誤りを本文の error で表す形だけを示し、HTTP のステータスを書いていないので、
// GitHub には 200 で返し、本文の error で誤りを表す。
func writeTokenError(w http.ResponseWriter, r *http.Request, provider string, status int, code, description string) {
	if provider == GitHub {
		if githubCode, ok := githubErrorCodes[code]; ok {
			code = githubCode
		}
		writeGitHubToken(w, r, http.StatusOK, url.Values{"error": {code}, "error_description": {description}})
		return
	}
	writeJSON(w, r, status, map[string]string{"error": code, "error_description": description})
}

// writeGitHubToken は、GitHub の token の口の応答を返す。GitHub の文書のとおり、Accept が JSON を求めるときは JSON で、
// そうでないときは URL の形で符号化した本文で返す。
func writeGitHubToken(w http.ResponseWriter, r *http.Request, status int, values url.Values) {
	if strings.Contains(r.Header.Get("Accept"), "application/json") {
		body := map[string]string{}
		for name := range values {
			body[name] = values.Get(name)
		}
		writeJSON(w, r, status, body)
		return
	}
	w.Header().Set("Content-Type", "application/x-www-form-urlencoded; charset=utf-8")
	w.WriteHeader(status)
	writeBody(w, r, []byte(values.Encode()))
}

// grantOf は、要求の Authorization のアクセストークンが指すものを返す。
func (s *Server) grantOf(r *http.Request, provider string) (grant, bool) {
	scheme, accessToken, ok := strings.Cut(r.Header.Get("Authorization"), " ")
	if !ok || !strings.EqualFold(scheme, "Bearer") {
		return grant{}, false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	g, ok := s.tokens[strings.TrimSpace(accessToken)]
	return g, ok && g.provider == provider
}

// googleUserInfo は、Google の userinfo の口である。
func (s *Server) googleUserInfo(w http.ResponseWriter, r *http.Request) {
	g, ok := s.grantOf(r, Google)
	if !ok {
		w.Header().Set("WWW-Authenticate", `Bearer error="invalid_token"`)
		writeJSON(w, r, http.StatusUnauthorized, map[string]string{"error": "invalid_token", "error_description": "アクセストークンが違います"})
		return
	}
	writeJSON(w, r, http.StatusOK, g.google)
}

// githubUserInfo は、GitHub の /user の口である。本物と同じく、公開していないメールアドレスは null で返す。
func (s *Server) githubUserInfo(w http.ResponseWriter, r *http.Request) {
	g, ok := s.grantOf(r, GitHub)
	if !ok {
		writeGitHubUnauthorized(w, r)
		return
	}
	writeJSON(w, r, http.StatusOK, map[string]any{"id": g.github.ID, "login": g.github.Login, "email": nil})
}

// githubEmails は、GitHub の /user/emails の口である。
func (s *Server) githubEmails(w http.ResponseWriter, r *http.Request) {
	g, ok := s.grantOf(r, GitHub)
	if !ok {
		writeGitHubUnauthorized(w, r)
		return
	}
	emails := g.github.Emails
	if emails == nil {
		emails = []GitHubEmail{}
	}
	writeJSON(w, r, http.StatusOK, emails)
}

func writeGitHubUnauthorized(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, r, http.StatusUnauthorized, map[string]string{"message": "Bad credentials", "status": "401"})
}

// putClient は、比べる検査が、提供元のクライアントの値を登録する口である。本文は Client.Form の形で受ける。
func (s *Server) putClient(w http.ResponseWriter, r *http.Request) {
	provider := r.PathValue("provider")
	if provider != Google && provider != GitHub {
		http.Error(w, "提供元は google か github です: "+provider, http.StatusNotFound)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxBodySize)
	if err := r.ParseForm(); err != nil {
		http.Error(w, "登録する値を読めません: "+err.Error(), http.StatusBadRequest)
		return
	}
	for name := range r.PostForm {
		if name != "client_id" && name != "client_secret" && name != "redirect_uri" {
			http.Error(w, "知らない項目です: "+name, http.StatusBadRequest)
			return
		}
	}
	c := Client{ID: r.PostForm.Get("client_id"), Secret: r.PostForm.Get("client_secret"), RedirectURIs: r.PostForm["redirect_uri"]}
	s.SetClient(provider, c)
	w.WriteHeader(http.StatusNoContent)
}

// putGoogleUser は、比べる検査が、Google でログインする利用者を登録する口である。
func (s *Server) putGoogleUser(w http.ResponseWriter, r *http.Request) {
	var u GoogleUser
	if !decodeJSON(w, r, &u) {
		return
	}
	s.SetGoogleUser(u)
	w.WriteHeader(http.StatusNoContent)
}

// putGitHubUser は、比べる検査が、GitHub でログインする利用者を登録する口である。
func (s *Server) putGitHubUser(w http.ResponseWriter, r *http.Request) {
	var u GitHubUser
	if !decodeJSON(w, r, &u) {
		return
	}
	s.SetGitHubUser(u)
	w.WriteHeader(http.StatusNoContent)
}

func decodeJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodySize))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(v); err != nil {
		http.Error(w, "登録する値を読めません: "+err.Error(), http.StatusBadRequest)
		return false
	}
	return true
}

// notImplemented は、受けると決めていない口を、比べる検査で見つかるように 501 で断る。
func (s *Server) notImplemented(w http.ResponseWriter, r *http.Request) {
	slog.LogAttrs(r.Context(), slog.LevelWarn, "fakeoidc_unexpected_request",
		slog.String("method", r.Method), slog.String("uri", r.URL.RequestURI()))
	writeJSON(w, r, http.StatusNotImplemented, map[string]string{"error": "fakeoidc はこの口を受けません: " + r.Method + " " + r.URL.Path})
}

func writeJSON(w http.ResponseWriter, r *http.Request, status int, v any) {
	body, err := json.Marshal(v)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	writeBody(w, r, body)
}

func writeBody(w http.ResponseWriter, r *http.Request, body []byte) {
	if _, err := w.Write(body); err != nil {
		slog.LogAttrs(r.Context(), slog.LevelWarn, "fakeoidc_write_failed",
			slog.String("uri", r.URL.RequestURI()), slog.String("error", err.Error()))
	}
}
