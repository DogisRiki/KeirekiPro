//go:build compat

package fakeoidc

import (
	"net/http"
	"net/url"
)

// putDeny は、比べる検査が、提供元のログインの開始を1回断らせる口である。受けるたびに、その提供元の断る残りの回数を1増やす。
// 比べる検査は、Java 版の番と Go 版の番に1回ずつこの口を呼ぶので、2つの版のログインの開始が1回ずつ断られる。
func (s *Server) putDeny(w http.ResponseWriter, r *http.Request) {
	provider := r.PathValue("provider")
	if provider != Google && provider != GitHub {
		http.Error(w, "提供元は google か github です: "+provider, http.StatusNotFound)
		return
	}
	s.mu.Lock()
	s.denies[provider]++
	s.mu.Unlock()
	w.WriteHeader(http.StatusNoContent)
}

// takeDeny は、提供元 provider の断る残りの回数が1以上なら、1減らして真を返す。
func (s *Server) takeDeny(provider string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.denies[provider] < 1 {
		return false
	}
	s.denies[provider]--
	return true
}

// writeDenied は、利用者がログインを断ったときの本物の提供元と同じく、redirect_uri へ error=access_denied と state を付けて転送する。
func writeDenied(w http.ResponseWriter, redirect *url.URL, state string) {
	params := redirect.Query()
	params.Set("error", "access_denied")
	if state != "" {
		params.Set("state", state)
	}
	redirect.RawQuery = params.Encode()
	w.Header().Set("Location", redirect.String())
	w.WriteHeader(http.StatusFound)
}

// postReset は、比べる検査が、筋書きの始めと終わりに、両方の提供元の利用者の設定と断る残りの回数を初めの状態に戻す口である。
// クライアントの値は、検査の環境を起動したときに登録したものを使い続けるので、戻さない。
func (s *Server) postReset(w http.ResponseWriter, _ *http.Request) {
	s.Reset()
	w.WriteHeader(http.StatusNoContent)
}

// Reset は、両方の提供元の利用者の設定と断る残りの回数を初めの状態に戻す。
func (s *Server) Reset() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.googleUser = nil
	s.githubUser = nil
	s.denies = map[string]int{}
}
