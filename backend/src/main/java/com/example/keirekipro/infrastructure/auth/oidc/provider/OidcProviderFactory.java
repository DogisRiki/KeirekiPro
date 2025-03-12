package com.example.keirekipro.infrastructure.auth.oidc.provider;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.stereotype.Component;

/**
 * プロバイダー名や種別から取得するプロバイダーを提供するファクトリ
 */
@Component
public class OidcProviderFactory {

    private final Map<String, OidcProvider> providersById;

    /**
     * コンストラクタ
     * 利用可能なすべてのOidcProviderをDIで受け取り、マップに整理する
     *
     * @param providers 利用可能なすべてのプロバイダー
     */
    public OidcProviderFactory(List<OidcProvider> providers) {
        // 小文字のプロバイダー名（google, github）からプロバイダーへのマップ
        this.providersById = providers.stream()
                .collect(Collectors.toMap(
                        h -> h.getClass().getSimpleName().toLowerCase().replace("oidcprovider", ""),
                        Function.identity()));
    }

    /**
     * プロバイダー名からプロバイダーを取得する。
     *
     * @param providerName プロバイダー名（google, github）
     * @return 対応するプロバイダー
     * @throws RuntimeException 対応するプロバイダーが見つからない場合(不適切なプロバイダー名が渡ってきた場合)
     */
    public OidcProvider getProvider(String providerName) {
        OidcProvider provider = providersById.get(providerName.toLowerCase());
        if (provider == null) {
            throw new RuntimeException("不明なOIDCプロバイダー: " + providerName);
        }
        return provider;
    }
}
