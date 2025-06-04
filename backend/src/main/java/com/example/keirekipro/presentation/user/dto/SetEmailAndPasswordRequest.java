package com.example.keirekipro.presentation.user.dto;

import com.example.keirekipro.presentation.shared.validator.PasswordMatches;

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
    @Size(min = 8, max = 20, message = "パスワードは8文字以上20文字以内で入力してください。")
    @Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).+$", message = "パスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")
    private String password;

    private String confirmPassword;
}
