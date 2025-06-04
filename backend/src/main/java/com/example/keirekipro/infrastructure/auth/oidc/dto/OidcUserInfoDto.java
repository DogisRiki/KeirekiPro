package com.example.keirekipro.infrastructure.auth.oidc.dto;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * OIDCプロバイダーから取得したユーザー情報を標準化して保持するDTO
 * 各プロバイダーから返されるユーザー情報のフォーマットは異なるため、このクラスでアプリケーション内で統一された形式に変換して扱う
 */
@RequiredArgsConstructor
@Getter
@Builder
public class OidcUserInfoDto {

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
