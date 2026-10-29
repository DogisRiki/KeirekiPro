package com.example.keirekipro.usecase.auth.verification;

import java.time.Duration;

/**
 * 確認のリンクのトークンの種類
 * 種類ごとのリンクの期限を決める唯一の部品
 */
public enum EmailVerificationPurpose {

    /**
     * 登録のメールアドレスの確認
     */
    REGISTRATION(Duration.ofHours(24)),

    /**
     * アカウントのメールアドレスの確認
     */
    ACCOUNT_EMAIL(Duration.ofHours(24)),

    /**
     * 設定待ちのメールアドレスの確認
     */
    PENDING_EMAIL(Duration.ofHours(24)),

    /**
     * パスワードの再設定を求めたときのメールアドレスの確認
     */
    PASSWORD_RESET(Duration.ofMinutes(10));

    private final Duration linkValidity;

    EmailVerificationPurpose(Duration linkValidity) {
        this.linkValidity = linkValidity;
    }

    /**
     * リンクの期限の長さを返す
     *
     * @return リンクの期限の長さ
     */
    public Duration getLinkValidity() {
        return linkValidity;
    }
}
