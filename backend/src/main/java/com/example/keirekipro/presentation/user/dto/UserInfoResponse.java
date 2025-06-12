package com.example.keirekipro.presentation.user.dto;

import java.util.List;

import com.example.keirekipro.usecase.user.dto.UserInfoUseCaseDto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

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

    private boolean hasPassword;

    private String profileImage;

    private boolean twoFactorAuthEnabled;

    private List<String> authProviders;

    /**
     * ユースケースDTOからレスポンスへの変換を行う
     *
     * @param dto ユースケースDTO
     * @return レスポンス
     */
    public static UserInfoResponse convertToResponse(UserInfoUseCaseDto dto) {

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
