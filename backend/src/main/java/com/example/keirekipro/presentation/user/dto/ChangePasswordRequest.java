package com.example.keirekipro.presentation.user.dto;

import java.util.UUID;

import com.example.keirekipro.presentation.shared.validator.MaxUtf8Bytes;
import com.example.keirekipro.usecase.user.command.ChangePasswordCommand;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * パスワード変更リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class ChangePasswordRequest {

    @NotBlank(message = "現在のパスワードは入力必須です。")
    private String nowPassword;

    @NotBlank(message = "新しいパスワードは入力必須です。")
    @Size(min = 8, message = "新しいパスワードは8文字以上で、半角72文字以内で入力してください。全角の文字は1文字を半角3文字分として数えます。")
    @MaxUtf8Bytes(value = 72, message = "新しいパスワードは8文字以上で、半角72文字以内で入力してください。全角の文字は1文字を半角3文字分として数えます。")
    @Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).+$", message = "新しいパスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")
    private String newPassword;

    /**
     * ユースケースコマンドへ変換する
     *
     * @param userId ユーザーID
     * @return パスワード変更コマンド
     */
    public ChangePasswordCommand toCommand(UUID userId) {
        return new ChangePasswordCommand(userId, nowPassword, newPassword);
    }
}
