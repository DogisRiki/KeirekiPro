package com.example.keirekipro.usecase.auth.verification;

/**
 * 確認のリンクを受け付けた結果
 */
public enum EmailVerificationResult {

    /**
     * 確認を済ませた
     */
    VERIFIED,

    /**
     * 確認を済ませ、パスワードの再設定に進める
     */
    PASSWORD_RESET_READY,

    /**
     * 確認がすでに済んでいる
     */
    ALREADY_VERIFIED,

    /**
     * 期限切れか、新しいメールで使えなくなったリンク
     */
    EXPIRED,

    /**
     * 確認前の登録が消えたリンク
     */
    REGISTRATION_GONE,

    /**
     * メールアドレスをほかのアカウントが使っている
     */
    EMAIL_TAKEN,

    /**
     * 使えないリンク
     */
    INVALID
}
