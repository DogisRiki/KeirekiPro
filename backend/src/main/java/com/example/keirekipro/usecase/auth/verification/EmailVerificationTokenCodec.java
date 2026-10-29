package com.example.keirekipro.usecase.auth.verification;

import java.util.Optional;

/**
 * 確認のリンクのトークンを作り、読む部品
 * リンクが期限内かどうかと、最新のリンクかどうかは判断しない
 */
public interface EmailVerificationTokenCodec {

    /**
     * トークンを作る
     *
     * @param claims トークンの中身
     * @return 署名したトークン
     */
    String issue(EmailVerificationClaims claims);

    /**
     * トークンの署名と用途を確かめて中身を返す
     * リンクの期限が切れていても、署名が正しければ中身を返す
     *
     * @param token トークン
     * @return 署名と用途が正しければ中身、正しくなければ空
     */
    Optional<EmailVerificationClaims> read(String token);
}
