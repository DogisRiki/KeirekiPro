package com.example.keirekipro.presentation.user.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.dto.UpdateUserInfoRequest;
import com.example.keirekipro.presentation.user.dto.UserInfoResponse;
import com.example.keirekipro.usecase.user.UpdateUserInfoUseCase;
import com.example.keirekipro.usecase.user.dto.UpdateUserInfoUseCaseDto;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー情報更新コントローラー
 */
@RestController
@RequestMapping("/api/users/me")
@RequiredArgsConstructor
public class UpdateUserInfoController {

    private final UpdateUserInfoUseCase updateUserInfoUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * ユーザー情報更新エンドポイント
     */
    @PutMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.OK)
    public UserInfoResponse handle(
            @RequestParam(name = "username", required = false) String username,
            @RequestParam(name = "profileImage", required = false) MultipartFile profileImage,
            @RequestParam(name = "twoFactorAuthEnabled", required = false) boolean twoFactorAuthEnabled) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        UpdateUserInfoRequest request = new UpdateUserInfoRequest(username, profileImage, twoFactorAuthEnabled);
        UpdateUserInfoUseCaseDto dto = updateUserInfoUseCase.execute(request, userId);

        return UserInfoResponse.builder()
                .id(dto.getId().toString())
                .username(dto.getUsername())
                .profileImage(dto.getProfileImage())
                .twoFactorAuthEnabled(dto.isTwoFactorAuthEnabled())
                .build();
    }
}
