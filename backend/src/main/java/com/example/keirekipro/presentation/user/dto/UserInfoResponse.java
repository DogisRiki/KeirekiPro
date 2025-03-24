package com.example.keirekipro.presentation.user.dto;

import java.util.List;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.Value;

/**
 * ユーザー情報レスポンス
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class UserInfoResponse {

    private String id;
    private String email;
    private String username;
    private byte[] profileImage;
    private boolean twoFactorAuthEnabled;
    private List<AuthProviderInfo> authProviders;

    /**
     * 外部認証連携情報
     */
    @Value
    public static class AuthProviderInfo {
        private String id;
        private String providerType;
        private String providerUserId;
    }
}
