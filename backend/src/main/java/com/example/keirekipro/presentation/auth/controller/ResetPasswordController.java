package com.example.keirekipro.presentation.auth.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.auth.dto.ResetPasswordRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.auth.ResetPasswordUseCase;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

import jakarta.validation.Valid;

/**
 * パスワードリセット実行コントローラー
 */
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class ResetPasswordController {

    private final ResetPasswordUseCase resetPasswordUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * パスワードリセット実行エンドポイント
     */
    @PostMapping("/password/reset")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "パスワードリセットの実行", description = "パスワードのリセット処理を実行する")
    public void handle(@RequestBody @Valid ResetPasswordRequest request) {
        String userId = currentUserFacade.getUserId();
        resetPasswordUseCase.execute(UUID.fromString(userId), request.getPassword());
    }
}
