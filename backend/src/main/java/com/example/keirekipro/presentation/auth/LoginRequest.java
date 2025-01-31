package com.example.keirekipro.presentation.auth;

import lombok.Value;

import jakarta.validation.constraints.NotBlank;

/**
 * ログインリクエスト
 */
@Value
public class LoginRequest {

    @NotBlank(message = "メールアドレスは入力必須です。")
    private String email;

    @NotBlank(message = "パスワードは入力必須です。")
    private String password;
}
