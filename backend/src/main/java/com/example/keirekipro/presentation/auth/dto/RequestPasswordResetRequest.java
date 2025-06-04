package com.example.keirekipro.presentation.auth.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

/**
 * パスワードリセット要求DTO
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class RequestPasswordResetRequest {

    @NotBlank(message = "メールアドレスは入力必須です。")
    @Email(message = "メールアドレスの形式が無効です。")
    private String email;
}
