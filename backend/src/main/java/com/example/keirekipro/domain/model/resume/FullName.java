package com.example.keirekipro.domain.model.resume;

import com.example.keirekipro.shared.Notification;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * 氏名
 */
@Getter
@EqualsAndHashCode
public class FullName {

    /**
     * 許可する文字列
     */
    public static final String ARROW_PATTERN = "^[a-zA-Zぁ-んァ-ン一-龯]+$";

    /**
     * 姓
     */
    private final String lastName;

    /**
     * 名
     */
    private final String firstName;

    private FullName(Notification notification, String lastName, String firstName) {
        validate(notification, lastName, firstName);
        this.lastName = lastName;
        this.firstName = firstName;
    }

    /**
     * ファクトリーメソッド
     *
     * @param notification 通知オブジェクト
     * @param lastName     姓
     * @param firstName    名
     * @return 値オブジェクト
     */
    public static FullName create(Notification notification, String lastName, String firstName) {
        return new FullName(notification, lastName, firstName);
    }

    private void validate(Notification notification, String lastName, String firstName) {
        if (lastName == null || lastName.isBlank()) {
            notification.addError("lastName", "姓は入力必須です。");
        } else {
            if (lastName.length() > 10) {
                notification.addError("lastName", "姓は10文字以内で入力してください。");
            }
            if (isInvalidValue(lastName)) {
                notification.addError("lastName", "姓には英数、ひらがな、カタカナ、漢字のみ使用できます。");
            }
        }
        if (firstName == null || firstName.isBlank()) {
            notification.addError("firstName", "名は入力必須です。");
        } else {
            if (firstName.length() > 10) {
                notification.addError("firstName", "名は10文字以内で入力してください。");
            }
            if (isInvalidValue(firstName)) {
                notification.addError("firstName", "名には英数、ひらがな、カタカナ、漢字のみ使用できます。");
            }
        }
    }

    /**
     * 禁止文字が含まれているかを検証する
     *
     * @param lastName  姓
     * @param firstName 名
     * @return 検証結果
     */
    private boolean isInvalidValue(String field) {
        return !field.matches(ARROW_PATTERN);
    }
}
