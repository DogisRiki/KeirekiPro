package com.example.keirekipro.usecase.shared.exception;

import lombok.Getter;

/**
 * メールアドレスの確認がまだのときにログインを断る例外
 */
@Getter
public class EmailNotVerifiedUseCaseException extends UseCaseException {

    private static final String EMAIL_NOT_VERIFIED_MESSAGE = "メールアドレスの確認が済んでいません。";

    /**
     * 確認がまだのものの種類
     */
    private final Kind kind;

    /**
     * 確認がまだのものの種類を指定するコンストラクタ
     *
     * @param kind 確認がまだのものの種類
     */
    public EmailNotVerifiedUseCaseException(Kind kind) {
        super(EMAIL_NOT_VERIFIED_MESSAGE);
        this.kind = kind;
    }

    /**
     * 確認がまだのものの種類
     */
    public enum Kind {

        /**
         * 確認前の登録
         */
        PENDING_REGISTRATION,

        /**
         * アカウントのメールアドレスの確認がまだ
         */
        UNVERIFIED_ACCOUNT_EMAIL
    }
}
