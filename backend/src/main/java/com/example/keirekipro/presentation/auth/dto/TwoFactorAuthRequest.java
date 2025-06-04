package com.example.keirekipro.presentation.auth.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;

/**
 * 二段階認証コードリクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class TwoFactorAuthRequest {

    private String userId;

    @NotBlank(message = "認証コードは入力必須です。")
    private String code;
}
