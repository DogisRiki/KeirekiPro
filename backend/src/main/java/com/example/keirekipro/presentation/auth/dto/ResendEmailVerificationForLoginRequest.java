package com.example.keirekipro.presentation.auth.dto;

import com.example.keirekipro.usecase.auth.command.ResendEmailVerificationForLoginCommand;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;

/**
 * ログインの画面から確認のメールを送るリクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class ResendEmailVerificationForLoginRequest {

    @NotBlank(message = "メールアドレスは入力必須です。")
    private String email;

    @NotBlank(message = "パスワードは入力必須です。")
    private String password;

    /**
     * ユースケースコマンドへ変換する
     *
     * @return ログインの画面から確認のメールを送るコマンド
     */
    public ResendEmailVerificationForLoginCommand toCommand() {
        return new ResendEmailVerificationForLoginCommand(email, password);
    }
}
