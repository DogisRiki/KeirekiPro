package com.example.keirekipro.presentation.auth.controller;

import com.example.keirekipro.presentation.auth.dto.RequestPasswordResetVerifyRequest;
import com.example.keirekipro.usecase.auth.VerifyPasswordResetTokenUseCase;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * パスワードリセットリンク検証コントローラー
 */
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class VerifyPasswordResetTokenController {

    private final VerifyPasswordResetTokenUseCase verifyPasswordResetTokenUseCase;

    /**
     * パスワードリセットリンク検証エンドポイント
     */
    @PostMapping("/password/reset/verify")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "パスワードリセットリンクの検証", description = "パスワードのリセットリンクの検証を行う")
    public void handle(@RequestBody RequestPasswordResetVerifyRequest request) {
        verifyPasswordResetTokenUseCase.execute(request.getToken());
    }
}
