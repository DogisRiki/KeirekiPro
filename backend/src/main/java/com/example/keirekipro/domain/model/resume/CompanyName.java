package com.example.keirekipro.domain.model.resume;

import com.example.keirekipro.shared.Notification;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * 会社名
 */
@Getter
@EqualsAndHashCode
public class CompanyName {

    private final String value;

    private CompanyName(Notification notification, String value) {
        validate(notification, value);
        this.value = value;
    }

    /**
     * ファクトリーメソッド
     *
     * @param notification 通知オブジェクト
     * @param value        会社名
     * @return 値オブジェクト
     */
    public static CompanyName create(Notification notification, String value) {
        return new CompanyName(notification, value);
    }

    private void validate(Notification notification, String value) {
        if (value == null || value.isBlank()) {
            notification.addError("companyName", "会社名は入力必須です。");
            return;
        }
        if (value.length() > 50) {
            notification.addError("companyName", "会社名は50文字以内で入力してください。");
        }
    }
}
