package com.example.keirekipro.infrastructure.auth.oidc.provider;

import java.util.Map;
import java.util.function.Consumer;

import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.fasterxml.jackson.databind.JsonNode;

import org.springframework.http.HttpHeaders;

/**
 * OIDCプロバイダー固有の処理を扱うインターフェース
 */
public interface OidcProvider {

    /**
     * 対応するプロバイダー種別を返す
     *
     * @return プロバイダー種別の識別子
     */
    String getProviderType();

    /**
     * プロバイダー固有のヘッダーを設定する
     *
     * @param headers 設定対象のHTTPヘッダー
     */
    void configureHeaders(HttpHeaders headers);

    /**
     * 認可エンドポイントのURLを返す
     *
     * @return 認可エンドポイントURL
     */
    String getAuthorizationEndpoint();

    /**
     * トークンエンドポイントのURLを返す
     *
     * @return トークンエンドポイントURL
     */
    String getTokenEndpoint();

    /**
     * ユーザー情報エンドポイントのURLを返す
     *
     * @return ユーザー情報エンドポイントURL
     */
    String getUserInfoEndpoint();

    /**
     * 要求するスコープを返す。
     *
     * @return スコープ（スペース区切り）
     */
    String getScopes();

    /**
     * AWS Secrets Managerのシークレット名を返す
     *
     * @return シークレット名
     */
    String getSecretName();

    /**
     * 認可URLにプロバイダー固有のパラメータを追加する
     *
     * @param params パラメータを追加するコンシューマ
     */
    default void addAuthorizationUrlParameters(Consumer<Map<String, String>> params) {
        // デフォルトでは何も追加しない
    }

    /**
     * プロバイダー固有のユーザー情報を標準形式に変換する
     *
     * @param userInfo プロバイダーから取得した生のユーザー情報
     * @return 標準化されたユーザー情報
     */
    OidcUserInfoDto convertToStandardUserInfo(Map<String, Object> userInfo);

    /**
     * Secrets Managerから取得したプロバイダー固有のシークレット情報を処理する
     *
     * @param secrets  シークレット情報のJsonNode
     * @param formData フォームデータに追加するコンシューマ
     */
    default void processSecrets(JsonNode secrets, Consumer<Map<String, String>> formData) {
        String clientId = secrets.get("client_id").asText();
        String clientSecret = secrets.get("client_secret").asText();

        formData.accept(Map.of(
                "client_id", clientId,
                "client_secret", clientSecret));
    }
}
