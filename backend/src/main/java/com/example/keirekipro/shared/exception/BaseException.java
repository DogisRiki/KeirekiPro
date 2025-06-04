package com.example.keirekipro.shared.exception;

import java.util.Collections;
import java.util.List;
import java.util.Map;

import lombok.Getter;

/**
 * アプリケーション全体の基底例外クラス
 */
@Getter
public abstract class BaseException extends RuntimeException {

    /**
     * エラーが発生したフィールド名とエラーメッセージのマップ
     */
    private final Map<String, List<String>> errors;

    /**
     * メッセージとフィールドエラーを指定するコンストラクタ
     *
     * @param message エラーメッセージ
     * @param errors  フィールドエラーのマップ
     */
    public BaseException(String message, Map<String, List<String>> errors) {
        super(message);
        this.errors = errors != null ? Collections.unmodifiableMap(errors) : Collections.emptyMap();
    }

    /**
     * メッセージのみのコンストラクタ（フィールドエラーなし）
     *
     * @param message エラーメッセージ
     */
    public BaseException(String message) {
        super(message);
        this.errors = Collections.emptyMap();
    }
}
