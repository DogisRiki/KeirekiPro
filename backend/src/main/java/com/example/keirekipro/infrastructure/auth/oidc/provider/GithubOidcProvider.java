package com.example.keirekipro.infrastructure.auth.oidc.provider;

import java.util.List;
import java.util.Map;

import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

/**
 * Githube固有のOIDC処理を実装するクラス
 */
@Component
public class GithubOidcProvider implements OidcProvider {

    private final RestClient restClient;
    private final ObjectMapper objectMapper;

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
            @Value("${oidc.providers.github.secretName}") String secretName,
            RestClient restClient,
            ObjectMapper objectMapper) {
        this.authorizationEndpoint = authorizationEndpoint;
        this.tokenEndpoint = tokenEndpoint;
        this.userInfoEndpoint = userInfoEndpoint;
        this.scopes = scopes;
        this.secretName = secretName;
        this.restClient = restClient;
        this.objectMapper = objectMapper;
    }

    @Override
    public String getProviderType() {
        return "github";
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

        String id = String.valueOf(userInfo.get("id"));
        String email = (String) userInfo.get("email");
        String username = (String) userInfo.get("login");

        // メールがnullの場合は /user/emails から取得
        if (email == null) {
            email = fetchPrimaryEmail((String) userInfo.get("access_token"));
        }

        return OidcUserInfoDto.builder()
                .providerUserId(id)
                .email(email)
                .username(username)
                .providerType(getProviderType())
                .build();
    }

    /**
     * GitHub API からユーザーのプライマリメールアドレスを取得する
     *
     * @param accessToken アクセストークン
     * @return プライマリかつverifiedなメールアドレス
     */
    private String fetchPrimaryEmail(String accessToken) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setBearerAuth(accessToken);
            configureHeaders(headers);

            // GETリクエストを実行
            String response = restClient.get()
                    .uri("https://api.github.com/user/emails")
                    .headers(h -> h.addAll(headers))
                    .retrieve()
                    .body(String.class);

            List<Map<String, Object>> emails = objectMapper.readValue(response, new TypeReference<>() {
            });

            return emails.stream()
                    .filter(e -> Boolean.TRUE.equals(e.get("primary")) && Boolean.TRUE.equals(e.get("verified")))
                    .map(e -> (String) e.get("email"))
                    .findFirst()
                    .orElse(null);
        } catch (Exception e) {
            return null;
        }
    }
}
