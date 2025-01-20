package com.example.keirekipro.domain.model.resume;

import java.util.Objects;

import com.example.keirekipro.domain.shared.Notification;

import lombok.Getter;

/**
 * 氏名
 */
@Getter
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
     * 生成メソッド
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
        if (isInvalidValue(lastName)) {
            notification.addError("lastName", "姓には英数、ひらがな、カタカナ、漢字のみ使用できます。");
        }
        if (isInvalidValue(firstName)) {
            notification.addError("firstName", "名には英数、ひらがな、カタカナ、漢字のみ使用できます。");
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

    @Override
    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (obj == null || getClass() != obj.getClass()) {
            return false;
        }
        FullName fullName = (FullName) obj;
        return Objects.equals(lastName, fullName.lastName) && Objects.equals(firstName, fullName.firstName);
    }

    @Override
    public int hashCode() {
        return Objects.hash(lastName, firstName);
    }
}
