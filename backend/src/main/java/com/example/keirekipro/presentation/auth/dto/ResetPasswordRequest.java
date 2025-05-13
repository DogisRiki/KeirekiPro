package com.example.keirekipro.presentation.auth.dto;

import com.example.keirekipro.presentation.shared.validator.PasswordMatches;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * パスワードリセット実行リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
@PasswordMatches(message = "新しいパスワードと新しいパスワード(確認)が一致していません。")
public class ResetPasswordRequest {

    @NotBlank(message = "新しいパスワードは入力必須です。")
    @Size(min = 8, max = 20, message = "新しいパスワードは8文字以上20文字以内で入力してください。")
    @Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).+$", message = "新しいパスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")
    private String password;

    @NotBlank(message = "新しいパスワード(確認)は入力必須です。")
    private String confirmPassword;

    private String token;
}
