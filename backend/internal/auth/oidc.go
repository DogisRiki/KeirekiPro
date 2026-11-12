package auth

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"strings"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
)

// このファイルは、Java 版の StartOidcAuthorizationUseCase と RedisOidcAuthorizationSessionStore と、
// OidcClient の buildAuthorizationUrl と、OidcProviderFactory の getProvider を写す。
// ログインの開始の記録は、oidc:state:<state> に state を、oidc:provider:<state> に受けたままの provider を、
// oidc:code_verifier:<state> に code_verifier を、どれも JSON の文字列で10分置く。

const (
	oidcStateKeyPrefix        = "oidc:state:"
	oidcProviderKeyPrefix     = "oidc:provider:"
	oidcCodeVerifierKeyPrefix = "oidc:code_verifier:"
	// oidcSessionValidity は、ログインの開始の記録の有効な時間である(Java 版の StartOidcAuthorizationUseCase)。
	oidcSessionValidity = 10 * time.Minute
)

// oidcProvider は、provider の名前に当たる Google か GitHub の設定を返す。Java 版の OidcProviderFactory と同じく、
// 名前の大文字と小文字を区別しない。どちらでもなければ偽を返す。
func (s *Service) oidcProvider(name string) (config.Provider, bool) {
	switch strings.ToLower(name) {
	case "google":
		return s.deps.OIDC.Google, true
	case "github":
		return s.deps.OIDC.GitHub, true
	}
	return config.Provider{}, false
}

// StartOIDC は、Java 版の StartOidcAuthorizationUseCase と同じく、Google か GitHub のログインの開始の URL を返す。
// code_verifier と state を、この順に32バイトの乱数の base64url で作り、ログインの開始の記録を10分置いてから、
// 接続先のあとに client_id、response_type、scope、redirect_uri、state、code_challenge、code_challenge_method を
// この順に並べた URL を作る。問い合わせの部分は、Spring の UriComponentsBuilder と同じ規則でエスケープする。
//
// Google と GitHub のほかの provider は、記録を置かずに 400 の「入力エラーがあります。」で断る。
// Java 版は、記録を置いたあとに URL を作るところで例外にし、500 で答えて記録を残す。この違いは変えた動きの一覧に載せる。
func (s *Service) StartOIDC(ctx context.Context, provider, redirectURI string) (string, error) {
	p, ok := s.oidcProvider(provider)
	if !ok {
		return "", errInvalidInput(map[string][]string{})
	}
	verifier, err := randomToken(s.deps.Random)
	if err != nil {
		return "", err
	}
	state, err := randomToken(s.deps.Random)
	if err != nil {
		return "", err
	}
	if err := s.storeOIDCSession(ctx, state, provider, verifier); err != nil {
		return "", err
	}
	query := springQuery([]queryParam{
		{"client_id", p.ClientID},
		{"response_type", "code"},
		{"scope", p.Scopes},
		{"redirect_uri", redirectURI},
		{"state", state},
		{"code_challenge", codeChallenge(verifier)},
		{"code_challenge_method", "S256"},
	})
	return p.AuthURL + "?" + query, nil
}

// storeOIDCSession は、Java 版の RedisOidcAuthorizationSessionStore の store と同じ順で、
// provider、state、code_verifier の記録を10分置く。
func (s *Service) storeOIDCSession(ctx context.Context, state, provider, verifier string) error {
	if err := s.setJSON(ctx, oidcProviderKeyPrefix+state, provider, oidcSessionValidity); err != nil {
		return err
	}
	if err := s.setJSON(ctx, oidcStateKeyPrefix+state, state, oidcSessionValidity); err != nil {
		return err
	}
	return s.setJSON(ctx, oidcCodeVerifierKeyPrefix+state, verifier, oidcSessionValidity)
}

// codeChallenge は、Java 版の SecurityUtil の generateCodeChallenge と同じく、code_verifier の UTF-8 のバイトの
// SHA-256 を、= の無い base64url にする(RFC 7636 の S256)。
func codeChallenge(verifier string) string {
	sum := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}
