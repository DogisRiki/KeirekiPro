package com.example.keirekipro.usecase.user.command;

import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * メールアドレス・パスワード設定ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class SetEmailAndPasswordCommand {

    private UUID userId;

    private String email;

    private String password;
}
