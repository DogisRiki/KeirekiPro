package com.example.keirekipro.usecase.auth.oidc;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * OIDC認可セッション
 */
@RequiredArgsConstructor
@Getter
@Builder
public class OidcAuthorizationSession {

    /**
     * state値
     */
    private final String state;

    /**
     * プロバイダー名
     */
    private final String provider;

    /**
     * code_verifier
     */
    private final String codeVerifier;
}
