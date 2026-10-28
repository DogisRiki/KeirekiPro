package com.example.keirekipro.usecase.auth.oidc;

import com.example.keirekipro.usecase.shared.exception.UseCaseException;

/**
 * メールアドレスの確認がまだのアカウントへ外部連携を結び付けないときの例外
 */
public class UnverifiedEmailAccountUseCaseException extends UseCaseException {

    private static final String UNVERIFIED_EMAIL_ACCOUNT_MESSAGE = "メールアドレスの確認が済んでいないアカウントには外部連携を結び付けられません。";

    /**
     * コンストラクタ
     */
    public UnverifiedEmailAccountUseCaseException() {
        super(UNVERIFIED_EMAIL_ACCOUNT_MESSAGE);
    }
}
