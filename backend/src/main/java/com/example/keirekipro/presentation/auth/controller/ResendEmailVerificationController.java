package com.example.keirekipro.presentation.auth.controller;

import com.example.keirekipro.presentation.auth.dto.EmailVerificationTokenRequest;
import com.example.keirekipro.usecase.auth.ResendEmailVerificationUseCase;

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
 * 使えなくなった確認のリンクから確認のメールを送り直すコントローラー
 */
@RestController
@RequestMapping("/api/auth/email-verification")
@RequiredArgsConstructor
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class ResendEmailVerificationController {

    private final ResendEmailVerificationUseCase resendEmailVerificationUseCase;

    /**
     * 確認のメールを送り直すエンドポイント
     */
    @PostMapping("/resend")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "確認のメールの送り直し", description = "期限の切れた確認のリンクのトークンから、確認のメールを送り直す")
    public void handle(@Valid @RequestBody EmailVerificationTokenRequest request) {
        resendEmailVerificationUseCase.execute(request.getToken());
    }
}
