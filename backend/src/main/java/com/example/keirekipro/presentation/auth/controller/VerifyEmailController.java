package com.example.keirekipro.presentation.auth.controller;

import com.example.keirekipro.presentation.auth.dto.EmailVerificationTokenRequest;
import com.example.keirekipro.presentation.auth.dto.VerifyEmailResponse;
import com.example.keirekipro.usecase.auth.VerifyEmailUseCase;

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
 * 確認のリンクを受け付けるコントローラー
 */
@RestController
@RequestMapping("/api/auth/email-verification")
@RequiredArgsConstructor
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class VerifyEmailController {

    private final VerifyEmailUseCase verifyEmailUseCase;

    /**
     * 確認のリンクを受け付けるエンドポイント
     * 画面が結果ごとに文を出し分けるため、どの結果でも 200 を返す
     */
    @PostMapping("/verify")
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "メールアドレスの確認", description = "確認のリンクのトークンを受け付け、確認の結果を返す")
    public VerifyEmailResponse handle(@Valid @RequestBody EmailVerificationTokenRequest request) {
        return VerifyEmailResponse.convertToResponse(verifyEmailUseCase.execute(request.getToken()));
    }
}
