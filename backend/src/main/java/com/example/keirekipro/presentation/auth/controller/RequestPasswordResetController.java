package com.example.keirekipro.presentation.auth.controller;

import com.example.keirekipro.presentation.auth.dto.RequestPasswordResetRequest;
import com.example.keirekipro.usecase.auth.RequestPasswordResetUseCase;

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
 * パスワードリセット要求コントローラー
 */
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class RequestPasswordResetController {

    private final RequestPasswordResetUseCase requestPasswordResetUseCase;

    /**
     * パスワードリセット要求エンドポイント
     */
    @PostMapping("/password/reset/request")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "パスワードリセット要求", description = "パスワードリセットの要求をを行い、パスワードリセットリンクを送信する")
    public void handle(@RequestBody @Valid RequestPasswordResetRequest request) {
        requestPasswordResetUseCase.execute(request.getEmail());
    }
}
