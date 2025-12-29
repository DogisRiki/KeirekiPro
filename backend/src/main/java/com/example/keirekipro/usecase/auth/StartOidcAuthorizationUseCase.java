package com.example.keirekipro.usecase.auth;

import java.time.Duration;

import com.example.keirekipro.shared.utils.SecurityUtil;
import com.example.keirekipro.usecase.auth.oidc.OidcGateway;
import com.example.keirekipro.usecase.auth.store.OidcAuthorizationSessionStore;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * OIDC認可フロー開始ユースケース
 */
@Service
@RequiredArgsConstructor
public class StartOidcAuthorizationUseCase {

    private final OidcGateway oidcGateway;
    private final OidcAuthorizationSessionStore oidcAuthorizationSessionStore;
    private final SecurityUtil securityUtil;

    /**
     * OIDC認可フローを開始し、認可URLを返す
     *
     * @param provider    プロバイダー名
     * @param redirectUri コールバックURI
     * @return 認可URL
     */
    public String execute(String provider, String redirectUri) {

        // PKCEパラメータを生成
        String codeVerifier = securityUtil.generateRandomToken();
        String codeChallenge = securityUtil.generateCodeChallenge(codeVerifier);

        // state値を生成
        String state = securityUtil.generateRandomToken();

        // 有効期限を10分に設定
        Duration expiration = Duration.ofMinutes(10);

        // state/provider/code_verifierを保存
        oidcAuthorizationSessionStore.store(state, provider, codeVerifier, expiration);

        // 認可URLの構築
        return oidcGateway.buildAuthorizationUrl(provider, redirectUri, state, codeChallenge);
    }
}
