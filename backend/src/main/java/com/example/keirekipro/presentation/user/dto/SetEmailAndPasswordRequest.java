package com.example.keirekipro.presentation.user.dto;

import java.util.UUID;

import com.example.keirekipro.presentation.shared.validator.MaxUtf8Bytes;
import com.example.keirekipro.presentation.shared.validator.PasswordMatches;
import com.example.keirekipro.usecase.user.command.SetEmailAndPasswordCommand;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * メールアドレス+パスワード設定リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
@PasswordMatches
public class SetEmailAndPasswordRequest {

    @Email(message = "メールアドレスの形式が無効です。")
    @Size(max = 255, message = "メールアドレスは255文字以内で入力してください。")
    private String email;

    @NotBlank(message = "パスワードは入力必須です。")
    @Size(min = 8, message = "パスワードは8文字以上で、半角72文字以内で入力してください。全角の文字は1文字を半角3文字分として数えます。")
    @MaxUtf8Bytes(value = 72, message = "パスワードは8文字以上で、半角72文字以内で入力してください。全角の文字は1文字を半角3文字分として数えます。")
    @Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).+$", message = "パスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")
    private String password;

    private String confirmPassword;

    private String currentPassword;

    /**
     * ユースケースコマンドへ変換する
     *
     * @param userId ユーザーID
     * @return メールアドレス・パスワード設定コマンド
     */
    public SetEmailAndPasswordCommand toCommand(UUID userId) {
        return new SetEmailAndPasswordCommand(userId, email, password, currentPassword);
    }
}
