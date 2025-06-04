package com.example.keirekipro.presentation.user.dto;

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
    @Size(min = 8, max = 20, message = "新しいパスワードは8文字以上20文字以内で入力してください。")
    @Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).+$", message = "新しいパスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")
    private String newPassword;
}
