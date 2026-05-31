package com.example.keirekipro.usecase.auth.command;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * ユーザー登録ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class UserRegistrationCommand {

    private String email;

    private String username;

    private String password;
}
