package com.example.keirekipro.usecase.auth.command;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * ログインユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class LoginCommand {

    private String email;

    private String password;
}
