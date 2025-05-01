package com.example.keirekipro.presentation.user.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.user.RemoveAuthProviderUseCase;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * 外部認証連携解除コントローラー
 */
@RestController
@RequestMapping("/api/users/me")
@RequiredArgsConstructor
public class RemoveAuthProviderController {

    private final RemoveAuthProviderUseCase removeAuthProviderUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 外部認証連携解除エンドポイント
     */
    @DeleteMapping("/auth-provider/{provider}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void handle(@PathVariable String provider) {
        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        removeAuthProviderUseCase.execute(userId, provider);
    }
}
