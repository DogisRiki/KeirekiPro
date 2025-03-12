package com.example.keirekipro.infrastructure.auth.oidc.provider;

import java.util.Map;

import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;

/**
 * Githube固有のOIDC処理を実装するクラス
 */
@Component
public class GithubOidcProvider implements OidcProvider {

    private final String authorizationEndpoint;
    private final String tokenEndpoint;
    private final String userInfoEndpoint;
    private final String scopes;
    private final String secretName;

    /**
     * コンストラクタ
     */
    public GithubOidcProvider(
            @Value("${oidc.providers.github.authorizationEndpoint}") String authorizationEndpoint,
            @Value("${oidc.providers.github.tokenEndpoint}") String tokenEndpoint,
            @Value("${oidc.providers.github.userInfoEndpoint}") String userInfoEndpoint,
            @Value("${oidc.providers.github.scopes}") String scopes,
            @Value("${oidc.providers.github.secretName}") String secretName) {
        this.authorizationEndpoint = authorizationEndpoint;
        this.tokenEndpoint = tokenEndpoint;
        this.userInfoEndpoint = userInfoEndpoint;
        this.scopes = scopes;
        this.secretName = secretName;
    }

    @Override
    public String getProviderType() {
        return "GITHUB";
    }

    @Override
    public void configureHeaders(HttpHeaders headers) {
        // GitHub固有のヘッダー設定
        headers.set(HttpHeaders.ACCEPT, "application/vnd.github+json");
        headers.set("X-GitHub-Api-Version", "2022-11-28");
    }

    @Override
    public String getAuthorizationEndpoint() {
        return authorizationEndpoint;
    }

    @Override
    public String getTokenEndpoint() {
        return tokenEndpoint;
    }

    @Override
    public String getUserInfoEndpoint() {
        return userInfoEndpoint;
    }

    @Override
    public String getScopes() {
        return scopes;
    }

    @Override
    public String getSecretName() {
        return secretName;
    }

    @Override
    public OidcUserInfoDto convertToStandardUserInfo(Map<String, Object> userInfo) {
        if (userInfo == null) {
            return null;
        }
        return OidcUserInfoDto.builder()
                .providerUserId(String.valueOf(userInfo.get("id")))
                .email((String) userInfo.get("email"))
                .username((String) userInfo.get("login"))
                .providerType(getProviderType())
                .build();
    }
}
