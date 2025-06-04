package com.example.keirekipro.presentation.user.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.dto.UpdateUserInfoRequest;
import com.example.keirekipro.presentation.user.dto.UserInfoResponse;
import com.example.keirekipro.usecase.user.GetUserInfoUseCase;
import com.example.keirekipro.usecase.user.UpdateUserInfoUseCase;
import com.example.keirekipro.usecase.user.dto.UserInfoUseCaseDto;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

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
@Tag(name = "users", description = "ユーザーに関するエンドポイント")
public class UpdateUserInfoController {

    private final UpdateUserInfoUseCase updateUserInfoUseCase;

    private final GetUserInfoUseCase getUserInfoUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * ユーザー情報更新エンドポイント
     */
    @PutMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "ユーザー情報の更新", description = "ユーザー情報の更新処理を実行する")
    public UserInfoResponse handle(
            @RequestParam(name = "username", required = false) String username,
            @RequestParam(name = "profileImage", required = false) MultipartFile profileImage,
            @RequestParam(name = "twoFactorAuthEnabled", required = false) boolean twoFactorAuthEnabled) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        UpdateUserInfoRequest request = new UpdateUserInfoRequest(username, profileImage, twoFactorAuthEnabled);
        updateUserInfoUseCase.execute(request, userId);
        UserInfoUseCaseDto dto = getUserInfoUseCase.execute(userId);
        return dto.convertToResponse(dto);
    }
}
