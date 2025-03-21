package com.example.keirekipro.presentation.auth.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * ユーザー新規登録リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class UserRegistrationRequest {

    @NotBlank(message = "メールアドレスは入力必須です。")
    @Size(max = 255, message = "メールアドレスは255文字以内で入力してください。")
    @Email(message = "メールアドレスの形式が無効です。")
    private String email;

    @NotBlank(message = "ユーザー名は入力必須です。")
    @Size(max = 50, message = "ユーザー名は50文字以内で入力してください。")
    private String username;

    @NotBlank(message = "パスワードは入力必須です。")
    @Size(min = 8, max = 20, message = "パスワードは8文字以上20文字以内で入力してください。")
    @Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).+$", message = "パスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")
    private String password;

    @NotBlank(message = "パスワード(確認用)は入力必須です。")
    private String confirmPassword;

    @AssertTrue(message = "パスワードとパスワード(確認用)が一致していません。")
    public boolean isPasswordMatching() {
        return password != null && password.equals(confirmPassword);
    }
}
