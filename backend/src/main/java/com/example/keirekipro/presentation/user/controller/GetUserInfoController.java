package com.example.keirekipro.presentation.user.controller;

import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.dto.UserInfoResponse;
import com.example.keirekipro.usecase.user.GetUserInfoUseCase;
import com.example.keirekipro.usecase.user.dto.GetUserInfoUseCaseDto;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー情報取得コントローラー
 */
@RestController
@RequestMapping("/api/users/me")
@RequiredArgsConstructor
@Tag(name = "users", description = "ユーザーに関するエンドポイント")
public class GetUserInfoController {

    private final GetUserInfoUseCase getUserInfoUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * ユーザー情報取得エンドポイント
     */
    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "ユーザー情報の取得", description = "ユーザー情報の取得を実行する")
    public UserInfoResponse handle() {
        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        GetUserInfoUseCaseDto dto = getUserInfoUseCase.execute(userId);
        return convertToResponse(dto);
    }

    /**
     * ユースケースDTOからレスポンスへの変換を行う
     *
     * @param dto ユースケースDTO
     * @return レスポンス
     */
    private UserInfoResponse convertToResponse(GetUserInfoUseCaseDto dto) {

        List<UserInfoResponse.AuthProviderInfo> authProviders = null;

        if (dto.getAuthProviders() != null) {
            authProviders = dto.getAuthProviders().stream()
                    .map(provider -> new UserInfoResponse.AuthProviderInfo(
                            provider.getId().toString(),
                            provider.getProviderType(),
                            provider.getProviderUserId()))
                    .collect(Collectors.toList());
        }

        return UserInfoResponse.builder()
                .id(dto.getId().toString())
                .email(dto.getEmail())
                .username(dto.getUsername())
                .profileImage(dto.getProfileImage())
                .twoFactorAuthEnabled(dto.isTwoFactorAuthEnabled())
                .authProviders(authProviders)
                .build();
    }
}
