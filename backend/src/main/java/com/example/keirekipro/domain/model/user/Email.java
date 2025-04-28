package com.example.keirekipro.domain.model.user;

import com.example.keirekipro.shared.Notification;

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

    private Email(Notification notification, String value) {
        validate(notification, value);
        this.value = value;
    }

    /**
     * ファクトリーメソッド
     *
     * @param notification 通知オブジェクト
     * @param value        メールアドレス
     * @return 値オブジェクト
     */
    public static Email create(Notification notification, String value) {
        return new Email(notification, value);
    }

    private void validate(Notification notification, String value) {
        if (value == null || value.isBlank()) {
            notification.addError("email", "メールアドレスが空です。");
            return;
        }
        if (!VALIDATOR.isValid(value)) {
            notification.addError("email", "メールアドレスの形式が不正です。");
        }
    }
}
