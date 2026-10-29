package com.example.keirekipro.usecase.auth.store;

/**
 * 確認のメールの送信間隔の制限ポート
 * 同じメールアドレスへの確認のメールを1分に1回までに抑える
 */
public interface EmailVerificationSendLimiter {

    /**
     * 送ってよいかを判定し、送ったことを記録する
     *
     * @param email メールアドレス
     * @return 送ってよい場合はtrue
     */
    boolean tryAcquire(String email);

    /**
     * 送ったことの記録を消す。メールの送信に失敗したときに使う
     *
     * @param email メールアドレス
     */
    void release(String email);
}
