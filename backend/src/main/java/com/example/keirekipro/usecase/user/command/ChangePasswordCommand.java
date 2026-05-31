package com.example.keirekipro.usecase.user.command;

import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * パスワード変更ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class ChangePasswordCommand {

    private UUID userId;

    private String nowPassword;

    private String newPassword;
}
