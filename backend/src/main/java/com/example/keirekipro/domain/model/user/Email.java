package com.example.keirekipro.domain.model.user;

import com.example.keirekipro.shared.ErrorCollector;

import org.apache.commons.validator.routines.EmailValidator;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * メールアドレス
 */
@Getter
@EqualsAndHashCode
public class Email {

    /**
     * RFC5322準拠チェックバリデーター
     */
    private static final EmailValidator VALIDATOR = EmailValidator.getInstance(false, false);

    private final String value;

    private Email(ErrorCollector errorCollector, String value) {
        validate(errorCollector, value);
        this.value = value;
    }

    /**
     * ファクトリーメソッド
     *
     * @param errorCollector エラー収集オブジェクト
     * @param value          メールアドレス
     * @return 値オブジェクト
     */
    public static Email create(ErrorCollector errorCollector, String value) {
        return new Email(errorCollector, value);
    }

    private void validate(ErrorCollector errorCollector, String value) {
        if (value == null || value.isBlank()) {
            errorCollector.addError("email", "メールアドレスが空です。");
            return;
        }
        if (!VALIDATOR.isValid(value)) {
            errorCollector.addError("email", "メールアドレスの形式が不正です。");
        }
    }
}
