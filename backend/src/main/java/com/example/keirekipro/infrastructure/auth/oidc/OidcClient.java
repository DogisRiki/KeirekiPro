package com.example.keirekipro.infrastructure.auth.oidc;

import java.util.HashMap;
import java.util.Map;

import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcTokenResponse;
import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.infrastructure.auth.oidc.provider.OidcProvider;
import com.example.keirekipro.infrastructure.auth.oidc.provider.OidcProviderFactory;
import com.example.keirekipro.infrastructure.shared.aws.AwsSecretsManagerClient;
import com.fasterxml.jackson.databind.JsonNode;

import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriComponentsBuilder;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

/**
 * OIDCプロバイダーとの通信を担当するクラス
 * プロバイダー固有の処理はOidcProviderに委譲する
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class OidcClient {

    /**
     * HTTP通信を行うためのRestClient
     */
    private final RestClient restClient;

    /**
     * OIDCプロバイダーを提供するファクトリー
     */
    private final OidcProviderFactory providerFactory;

    /**
     * AWS Secrets Managerからシークレット情報を取得するクライアント
     */
    private final AwsSecretsManagerClient secretsClient;

    /**
     * 認可URLを構築する
     * ユーザーがOIDCプロバイダーへリダイレクトされる際のURLを生成する
     *
     * @param providerName  プロバイダー名（"google", "github"など）
     * @param redirectUri   コールバックURI
     * @param state         CSRF対策用のstate値
     * @param codeChallenge PKCE用のcode_challenge
     * @return 構築された認可URL
     */
    public String buildAuthorizationUrl(String providerName, String redirectUri, String state, String codeChallenge) {
        // プロバイダー固有のOIDCプロバイダーを取得
        OidcProvider provider = providerFactory.getProvider(providerName);

        // AWS Secrets ManagerからクライアントIDを取得
        JsonNode secrets = secretsClient.getSecretJson(provider.getSecretName());
        String clientId = secrets.get("client_id").asText();

        // 認可URLを構築
        UriComponentsBuilder builder = UriComponentsBuilder
                .fromUriString(provider.getAuthorizationEndpoint())
                .queryParam("client_id", clientId)
                .queryParam("response_type", "code")
                .queryParam("scope", provider.getScopes())
                .queryParam("redirect_uri", redirectUri)
                .queryParam("state", state)
                .queryParam("code_challenge", codeChallenge)
                .queryParam("code_challenge_method", "S256");

        // プロバイダー固有のパラメータがあれば追加
        Map<String, String> extraParams = new HashMap<>();
        provider.addAuthorizationUrlParameters(extraParams::putAll);
        extraParams.forEach(builder::queryParam);

        return builder.toUriString();
    }

    /**
     * 認可コードを使用してアクセストークンを取得する
     *
     * @param providerName プロバイダー名
     * @param code         認可コード
     * @param redirectUri  リダイレクトURI
     * @param codeVerifier PKCE用のcode_verifier
     * @return トークンレスポンス
     */
    public OidcTokenResponse getToken(String providerName, String code, String redirectUri, String codeVerifier) {
        // プロバイダー固有のOIDCプロバイダーを取得
        OidcProvider provider = providerFactory.getProvider(providerName);

        // フォームデータ構築
        Map<String, String> formData = new HashMap<>();
        formData.put("grant_type", "authorization_code");
        formData.put("code", code);
        formData.put("redirect_uri", redirectUri);
        formData.put("code_verifier", codeVerifier);

        // AWS Secrets Managerからクライアント情報を取得
        JsonNode secrets = secretsClient.getSecretJson(provider.getSecretName());

        // プロバイダー固有のシークレット情報を処理
        provider.processSecrets(secrets, formData::putAll);

        try {
            MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
            formData.forEach(form::add);
            // トークンエンドポイントにPOSTリクエスト
            return restClient
                    .post()
                    .uri(provider.getTokenEndpoint())
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .header(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON_VALUE)
                    .body(form)
                    .retrieve()
                    .body(OidcTokenResponse.class);
        } catch (Exception e) {
            log.error("トークン取得でエラーが発生しました。プロバイダー: {}", providerName, e);
            OidcTokenResponse errorResponse = new OidcTokenResponse();
            errorResponse.setError("server_error");
            errorResponse.setErrorDescription("トークン取得処理中にエラーが発生しました: " + e.getMessage());
            return errorResponse;
        }
    }

    /**
     * userinfoエンドポイントからユーザー情報を取得する
     * 各プロバイダーから取得した異なる形式のユーザー情報を標準化して返す
     *
     * @param providerName プロバイダー名
     * @param accessToken  アクセストークン
     * @return 標準化されたユーザー情報
     */
    public OidcUserInfoDto getUserInfo(String providerName, String accessToken) {
        // プロバイダー固有のOIDCプロバイダーを取得
        OidcProvider provider = providerFactory.getProvider(providerName);

        // HTTPヘッダー構築
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(accessToken);

        // プロバイダー固有のヘッダー設定を適用
        provider.configureHeaders(headers);

        try {
            // ユーザー情報を取得
            Map<String, Object> userInfo = restClient
                    .get()
                    .uri(provider.getUserInfoEndpoint())
                    .headers(p -> p.addAll(headers))
                    .retrieve()
                    .body(new ParameterizedTypeReference<Map<String, Object>>() {
                    });

            if (userInfo == null) {
                return null;
            }

            // access_tokenをuserInfoに追加（GitHub 用）
            userInfo.put("access_token", accessToken);

            // プロバイダー固有の変換処理で標準形式に変換
            return provider.convertToStandardUserInfo(userInfo);
        } catch (Exception e) {
            log.error("ユーザー情報取得でエラーが発生しました。プロバイダー: {}", providerName, e);
            return null;
        }
    }
}
