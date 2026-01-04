package com.example.keirekipro.infrastructure.repository.user;

import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

import lombok.Data;

/**
 * ユーザーDTO
 */
@Data
public class UserDto {

    private UUID id;
    private String email;
    private String password;
    private String username;
    private String profileImage;
    private boolean twoFactorAuthEnabled;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
    private List<AuthProviderDto> authProviders;
    private List<String> roles;

    /**
     * 外部認証連携情報DTO
     */
    @Data
    public static class AuthProviderDto {
        private UUID id;
        private UUID userId;
        private String providerName;
        private String providerUserId;
        private LocalDateTime createdAt;
        private LocalDateTime updatedAt;
    }
}
