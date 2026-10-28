package com.example.keirekipro.usecase.auth.command;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * ログインの画面から確認のメールを送るユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class ResendEmailVerificationForLoginCommand {

    private String email;

    private String password;
}
