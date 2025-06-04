package com.example.keirekipro.domain.shared.exception;

import java.util.List;
import java.util.Map;

import com.example.keirekipro.shared.exception.BaseException;

/**
 * ドメイン層で発生した例外
 */
public class DomainException extends BaseException {

    private static final String DEFAULT_DOMAIN_ERROR_MESSAGE = "入力エラーがあります。";

    /**
     * フィールドエラーを指定するコンストラクタ
     *
     * @param errors フィールドエラーのマップ
     */
    public DomainException(Map<String, List<String>> errors) {
        super(DEFAULT_DOMAIN_ERROR_MESSAGE, errors);
    }

    /**
     * メッセージのみのコンストラクタ
     *
     * @param message エラーメッセージ
     */
    public DomainException(String message) {
        super(message);
    }

    /**
     * メッセージとフィールドエラーを指定するコンストラクタ
     *
     * @param message エラーメッセージ
     * @param errors  フィールドエラーのマップ
     */
    public DomainException(String message, Map<String, List<String>> errors) {
        super(message, errors);
    }
}
