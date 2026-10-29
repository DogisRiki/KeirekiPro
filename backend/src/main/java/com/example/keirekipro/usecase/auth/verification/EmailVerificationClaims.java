package com.example.keirekipro.usecase.auth.verification;

import java.time.Instant;
import java.util.UUID;

/**
 * 確認のリンクのトークンの中身
 *
 * @param jti リンクごとに作るID
 * @param subjectId 確認前の登録かアカウントのID
 * @param purpose トークンの種類
 * @param email 確認するメールアドレス
 * @param linkExpiresAt リンクの期限
 */
public record EmailVerificationClaims(
        String jti,
        UUID subjectId,
        EmailVerificationPurpose purpose,
        String email,
        Instant linkExpiresAt) {
}
