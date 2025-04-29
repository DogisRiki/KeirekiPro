package com.example.keirekipro.presentation.auth.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * パスワードリセットリンク検証リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class RequestPasswordResetVerifyRequest {

    private String token;
}
