package com.example.keirekipro.usecase.auth.oidc;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * OIDCユーザー情報
 */
@RequiredArgsConstructor
@Getter
@Builder
public class OidcUserInfo {

    /**
     * プロバイダー内でのユーザーID
     */
    private final String providerUserId;

    /**
     * メールアドレス
     */
    private final String email;

    /**
     * ユーザー名
     */
    private final String username;

    /**
     * プロバイダー種別
     */
    private final String providerType;
}
