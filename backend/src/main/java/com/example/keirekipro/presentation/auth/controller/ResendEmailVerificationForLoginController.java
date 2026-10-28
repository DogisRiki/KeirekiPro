package com.example.keirekipro.presentation.auth.controller;

import com.example.keirekipro.presentation.auth.dto.ResendEmailVerificationForLoginRequest;
import com.example.keirekipro.usecase.auth.ResendEmailVerificationForLoginUseCase;

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
 * ログインの画面から確認のメールを送るコントローラー
 */
@RestController
@RequestMapping("/api/auth/email-verification")
@RequiredArgsConstructor
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class ResendEmailVerificationForLoginController {

    private final ResendEmailVerificationForLoginUseCase resendEmailVerificationForLoginUseCase;

    /**
     * ログインの画面から確認のメールを送るエンドポイント
     */
    @PostMapping("/resend-for-login")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "ログインの画面からの確認のメールの送信", description = "メールアドレスとパスワードを確かめ、確認がまだのアカウントへ確認のメールを送る")
    public void handle(@Valid @RequestBody ResendEmailVerificationForLoginRequest request) {
        resendEmailVerificationForLoginUseCase.execute(request.toCommand());
    }
}
