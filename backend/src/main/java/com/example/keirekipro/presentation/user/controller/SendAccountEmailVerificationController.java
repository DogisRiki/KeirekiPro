package com.example.keirekipro.presentation.user.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.user.SendAccountEmailVerificationUseCase;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー設定の画面から確認のメールを送るコントローラー
 */
@RestController
@RequestMapping("/api/users/me")
@RequiredArgsConstructor
@Tag(name = "users", description = "ユーザーに関するエンドポイント")
public class SendAccountEmailVerificationController {

    private final SendAccountEmailVerificationUseCase sendAccountEmailVerificationUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * ログインしている利用者のアカウントに確認のメールを送るエンドポイント
     */
    @PostMapping("/email-verification")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "確認のメールの送信", description = "ログインしている利用者のアカウントの、確認がまだのメールアドレスに確認のメールを送る")
    public void handle() {
        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        sendAccountEmailVerificationUseCase.execute(userId);
    }
}
