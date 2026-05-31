package com.example.keirekipro.presentation.auth.dto;

import com.example.keirekipro.usecase.auth.command.LoginCommand;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;

/**
 * ログインリクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class LoginRequest {

    @NotBlank(message = "メールアドレスは入力必須です。")
    private String email;

    @NotBlank(message = "パスワードは入力必須です。")
    private String password;

    /**
     * ユースケースコマンドへ変換する
     *
     * @return ログインコマンド
     */
    public LoginCommand toCommand() {
        return new LoginCommand(email, password);
    }
}
