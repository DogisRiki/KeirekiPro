package com.example.keirekipro.presentation.user.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.dto.ChangePasswordRequest;
import com.example.keirekipro.usecase.user.ChangePasswordUseCase;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

import jakarta.validation.Valid;

/**
 * パスワード変更コントローラー
 */
@RestController
@RequestMapping("/api/users/me")
@RequiredArgsConstructor
@Tag(name = "users", description = "ユーザーに関するエンドポイント")
public class ChangePasswordController {

    private final ChangePasswordUseCase changePasswordUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * パスワード変更エンドポイント
     */
    @PatchMapping("/password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "パスワード変更", description = "パスワードの変更を実行する")
    public void handle(@Valid @RequestBody ChangePasswordRequest request) {
        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        changePasswordUseCase.execute(request, userId);
    }
}
