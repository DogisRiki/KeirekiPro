package com.example.keirekipro.presentation.auth.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 確認のリンクのトークンを送るリクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class EmailVerificationTokenRequest {

    @NotBlank(message = "トークンは入力必須です。")
    @Size(max = 2048, message = "トークンは2048文字以内で入力してください。")
    private String token;
}
