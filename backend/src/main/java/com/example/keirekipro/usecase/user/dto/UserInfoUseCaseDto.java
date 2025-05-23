package com.example.keirekipro.usecase.user.dto;

import java.util.List;
import java.util.UUID;

import com.example.keirekipro.presentation.user.dto.UserInfoResponse;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * ユーザー情報取得ユースケースDTO
 */
@RequiredArgsConstructor
@Getter
@Builder
public class UserInfoUseCaseDto {

    private final UUID id;
    private final String email;
    private final String username;
    private final boolean hasPassword;
    private final String profileImage;
    private final boolean twoFactorAuthEnabled;
    private final List<AuthProviderInfo> authProviders;

    /**
     * 外部認証連携情報
     */
    @RequiredArgsConstructor
    @Getter
    public static class AuthProviderInfo {
        private final UUID id;
        private final String providerName;
        private final String providerUserId;
    }

    /**
     * ユースケースDTOからレスポンスへの変換を行う
     *
     * @param dto ユースケースDTO
     * @return レスポンス
     */
    public UserInfoResponse convertToResponse(UserInfoUseCaseDto dto) {

        List<String> authProviders = null;

        if (dto.getAuthProviders() != null) {
            authProviders = dto.getAuthProviders().stream()
                    .map(provider -> provider.getProviderName())
                    .toList();
        }

        return UserInfoResponse.builder()
                .id(dto.getId().toString())
                .email(dto.getEmail())
                .username(dto.getUsername())
                .hasPassword(dto.isHasPassword())
                .profileImage(dto.getProfileImage())
                .twoFactorAuthEnabled(dto.isTwoFactorAuthEnabled())
                .authProviders(authProviders)
                .build();
    }
}
