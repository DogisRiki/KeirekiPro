package com.example.keirekipro.usecase.auth.dto;

import java.util.Set;
import java.util.UUID;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * OIDCログインユースDTO
 */
@RequiredArgsConstructor
@Getter
@Builder
public class OidcLoginUseCaseDto {

    /**
     * ユーザーID
     */
    private final UUID id;

    /**
     * ユーザー名
     */
    private final String username;

    /**
     * メールアドレス
     */
    private final String email;

    /**
     * 認証に使用されたOIDCプロバイダー種別
     */
    private final String providerType;

    /**
     * ロール
     */
    private final Set<String> roles;
}
