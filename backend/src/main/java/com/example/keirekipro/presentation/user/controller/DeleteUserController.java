package com.example.keirekipro.presentation.user.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.user.DeleteUserUseCase;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー退会コントローラー
 */
@RestController
@RequestMapping("api/users/me")
@RequiredArgsConstructor
public class DeleteUserController {

    private final DeleteUserUseCase deleteUserUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * ユーザー退会エンドポイント
     */
    @DeleteMapping
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteUser() {
        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        deleteUserUseCase.execute(userId);
    }
}
