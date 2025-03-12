package com.example.keirekipro.infrastructure.auth.oidc.provider;

import java.util.Map;

import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;

/**
 * Google固有のOIDC処理を実装するクラス
 */
@Component
public class GoogleOidcProvider implements OidcProvider {

    private final String authorizationEndpoint;
    private final String tokenEndpoint;
    private final String userInfoEndpoint;
    private final String scopes;
    private final String secretName;

    /**
     * コンストラクタ
     */
    public GoogleOidcProvider(
            @Value("${oidc.providers.google.authorizationEndpoint}") String authorizationEndpoint,
            @Value("${oidc.providers.google.tokenEndpoint}") String tokenEndpoint,
            @Value("${oidc.providers.google.userInfoEndpoint}") String userInfoEndpoint,
            @Value("${oidc.providers.google.scopes}") String scopes,
            @Value("${oidc.providers.google.secretName}") String secretName) {
        this.authorizationEndpoint = authorizationEndpoint;
        this.tokenEndpoint = tokenEndpoint;
        this.userInfoEndpoint = userInfoEndpoint;
        this.scopes = scopes;
        this.secretName = secretName;
    }

    @Override
    public String getProviderType() {
        return "GOOGLE";
    }

    @Override
    public void configureHeaders(HttpHeaders headers) {
        // Google固有のヘッダー設定（特に必要なし）
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
                .providerUserId((String) userInfo.get("sub"))
                .email((String) userInfo.get("email"))
                .username((String) userInfo.get("name"))
                .providerType(getProviderType())
                .build();
    }
}
