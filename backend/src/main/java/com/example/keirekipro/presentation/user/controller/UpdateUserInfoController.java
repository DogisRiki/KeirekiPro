package com.example.keirekipro.presentation.user.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.dto.UpdateUserInfoRequest;
import com.example.keirekipro.presentation.user.dto.UserInfoResponse;
import com.example.keirekipro.usecase.user.UpdateUserInfoUseCase;
import com.example.keirekipro.usecase.user.dto.UpdateUserInfoUseCaseDto;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * パスワード変更コントローラー
 */
@RestController
@RequestMapping("/api/users/me")
@RequiredArgsConstructor
public class UpdateUserInfoController {

    private UpdateUserInfoUseCase updateUserInfoUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * ユーザー情報更新エンドポイント
     */
    @PutMapping
    @ResponseStatus(HttpStatus.OK)
    public UserInfoResponse handle(@RequestBody UpdateUserInfoRequest request) {
        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        UpdateUserInfoUseCaseDto dto = updateUserInfoUseCase.execute(request, userId);
        return UserInfoResponse.builder()
                .id(dto.getId().toString())
                .username(dto.getUsername())
                .profileImage(dto.getProfileImage())
                .twoFactorAuthEnabled(dto.isTwoFactorAuthEnabled())
                .build();
    }
}
