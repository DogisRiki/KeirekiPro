package com.example.keirekipro.infrastructure.repository.user.dto;

import java.util.List;
import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * ユーザー情報DTO
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class UserInfo {

    private UUID id;
    private String email;
    private String username;
    private String profileImage;
    private boolean twoFactorAuthEnabled;
    private List<AuthProviderInfo> authProviders;

    /**
     * 外部認証連携情報
     */
    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class AuthProviderInfo {
        private UUID id;
        private String providerType;
        private String providerUserId;
    }
}
