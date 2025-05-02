package com.example.keirekipro.presentation.user.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.dto.SetEmailAndPasswordRequest;
import com.example.keirekipro.usecase.user.SetEmailAndPasswordUseCase;

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
 * メールアドレス+パスワード設定コントローラ
 */
@RestController
@RequestMapping("/api/users/me")
@RequiredArgsConstructor
@Tag(name = "users", description = "ユーザーに関するエンドポイント")
public class SetEmailAndPasswordController {

    private final SetEmailAndPasswordUseCase setEmailAndPasswordUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * メールアドレス+パスワード設定エンドポイント
     */
    @PostMapping("/email-password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "メールアドレスとパスワードの設定", description = "メールアドレスとパスワードの設定を実行する")
    public void handle(@Valid @RequestBody SetEmailAndPasswordRequest request) {
        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        setEmailAndPasswordUseCase.execute(userId, request);
    }
}
