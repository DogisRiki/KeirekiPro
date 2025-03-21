package com.example.keirekipro.usecase.shared;

import lombok.Getter;

/**
 * ユースケース層で発生した例外
 */
@Getter
public class UseCaseException extends RuntimeException {

    /**
     * デフォルトコンストラクタ
     *
     * @param message エラーメッセージ
     */
    public UseCaseException(String message) {
        super(message);
    }

    /**
     * 原因となる例外を指定するコンストラクタ
     *
     * @param message エラーメッセージ
     * @param cause   原因となる例外
     */
    public UseCaseException(String message, Throwable cause) {
        super(message, cause);
    }
}
