package com.example.keirekipro.usecase.user.dto;

import java.util.List;
import java.util.UUID;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * ユーザー情報取得ユースケースDTO
 */
@RequiredArgsConstructor
@Getter
@Builder
public class GetUserInfoUseCaseDto {

    private final UUID id;
    private final String email;
    private final String username;
    private final byte[] profileImage;
    private final boolean twoFactorAuthEnabled;
    private final List<AuthProviderInfo> authProviders;

    /**
     * 外部認証連携情報
     */
    @RequiredArgsConstructor
    @Getter
    public static class AuthProviderInfo {
        private final UUID id;
        private final String providerType;
        private final String providerUserId;
    }
}
