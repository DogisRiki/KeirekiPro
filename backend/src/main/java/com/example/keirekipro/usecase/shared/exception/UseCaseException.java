package com.example.keirekipro.usecase.shared.exception;

import java.util.List;
import java.util.Map;

import com.example.keirekipro.shared.exception.BaseException;

/**
 * ユースケース層で発生した例外
 */
public class UseCaseException extends BaseException {

    private static final String DEFAULT_USECASE_ERROR_MESSAGE = "入力エラーがあります。";

    /**
     * フィールドエラーを指定するコンストラクタ
     *
     * @param errors フィールドエラーのマップ
     */
    public UseCaseException(Map<String, List<String>> errors) {
        super(DEFAULT_USECASE_ERROR_MESSAGE, errors);
    }

    /**
     * メッセージのみのコンストラクタ
     *
     * @param message エラーメッセージ
     */
    public UseCaseException(String message) {
        super(message);
    }

    /**
     * メッセージとフィールドエラーを指定するコンストラクタ
     *
     * @param message エラーメッセージ
     * @param errors  フィールドエラーのマップ
     */
    public UseCaseException(String message, Map<String, List<String>> errors) {
        super(message, errors);
    }
}
