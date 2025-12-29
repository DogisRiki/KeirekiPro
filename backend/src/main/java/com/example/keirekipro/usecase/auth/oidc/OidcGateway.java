package com.example.keirekipro.usecase.auth.oidc;

/**
 * OIDC外部I/Oを抽象化するインターフェース
 */
public interface OidcGateway {

    /**
     * 認可URLを構築する
     *
     * @param provider      プロバイダー名
     * @param redirectUri   コールバックURI
     * @param state         CSRF対策用のstate値
     * @param codeChallenge PKCE用のcode_challenge
     * @return 認可URL
     */
    String buildAuthorizationUrl(String provider, String redirectUri, String state, String codeChallenge);

    /**
     * 認可コードを使用してアクセストークンを取得する
     *
     * @param provider     プロバイダー名
     * @param code         認可コード
     * @param redirectUri  リダイレクトURI
     * @param codeVerifier PKCE用のcode_verifier
     * @return トークン
     */
    OidcToken exchangeToken(String provider, String code, String redirectUri, String codeVerifier);

    /**
     * userinfoエンドポイントからユーザー情報を取得する
     *
     * @param provider    プロバイダー名
     * @param accessToken アクセストークン
     * @return ユーザー情報（取得失敗時はnull）
     */
    OidcUserInfo fetchUserInfo(String provider, String accessToken);
}
