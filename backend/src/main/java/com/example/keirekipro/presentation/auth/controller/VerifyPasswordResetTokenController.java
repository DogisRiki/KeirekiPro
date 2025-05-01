package com.example.keirekipro.presentation.auth.controller;

import com.example.keirekipro.presentation.auth.dto.RequestPasswordResetVerifyRequest;
import com.example.keirekipro.usecase.auth.VerifyPasswordResetTokenUseCase;

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
public class VerifyPasswordResetTokenController {

    private final VerifyPasswordResetTokenUseCase verifyPasswordResetTokenUseCase;

    /**
     * パスワードリセットリンク検証エンドポイント
     */
    @PostMapping("/password/reset/verify")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void handle(@RequestBody RequestPasswordResetVerifyRequest request) {
        verifyPasswordResetTokenUseCase.execute(request.getToken());
    }
}
