package com.example.keirekipro.presentation.auth.controller;

import com.example.keirekipro.presentation.auth.dto.UserRegistrationRequest;
import com.example.keirekipro.usecase.auth.UserRegistrationUseCase;

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
 * ユーザー新規登録コントローラー
 */
@RestController
@RequestMapping("/api/auth/register")
@RequiredArgsConstructor
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class UserRegistrationController {

    private final UserRegistrationUseCase userRegistrationUseCase;

    /**
     * ユーザー新規登録エンドポイント
     */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "ユーザー新規登録", description = "メールアドレスとパスワードによるユーザーの新規登録を行う")
    public void handle(@Valid @RequestBody UserRegistrationRequest request) {
        userRegistrationUseCase.execute(request);
    }
}
