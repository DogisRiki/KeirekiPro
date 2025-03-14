package com.example.keirekipro.presentation.auth.oidc.config;

import java.util.Map;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.Setter;

/**
 * プロパティファイル内のOIDC設定情報をマッピングするクラス
 */
@Configuration
@Getter
@RequiredArgsConstructor
@ConfigurationProperties(prefix = "oidc")
public class OidcProperties {

    private final Map<String, ProviderConfig> providers;

    /**
     * 指定されたプロバイダー名の設定を取得する
     *
     * @param providerName プロバイダー名（"google", "github"など）
     * @return プロバイダーの設定情報
     */
    public ProviderConfig getProvider(String providerName) {
        return providers.get(providerName);
    }

    /**
     * プロバイダー設定を保持する内部クラス
     */
    @Getter
    @Setter
    public static class ProviderConfig {
        private String authorizationEndpoint;
        private String tokenEndpoint;
        private String userInfoEndpoint;
        private String scopes;
        private String providerType;
        private String secretName;

        /**
         * コールバックURLを構築する
         *
         * @param baseUrl アプリケーションのベースURL
         * @return 完全なコールバックURL
         */
        public String buildCallbackUrl(String baseUrl) {
            return baseUrl + "/api/auth/oidc/callback";
        }
    }
}
