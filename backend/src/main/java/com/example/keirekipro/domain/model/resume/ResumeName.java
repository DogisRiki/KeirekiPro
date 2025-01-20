package com.example.keirekipro.domain.model.resume;

import com.example.keirekipro.domain.shared.Notification;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * 職務経歴書名
 */
@Getter
@EqualsAndHashCode
public class ResumeName {

    /**
     * 禁止する文字列
     */
    public static final String INVALID_PATTERN = "[\\\\/:*?\"<>|]";

    /**
     * 先頭または末尾に使用できない文字
     */
    public static final String INVALID_START_END_CHAR = ".";

    private final String value;

    private ResumeName(Notification notification, String value) {
        validate(notification, value);
        this.value = value;
    }

    /**
     * 生成メソッド
     *
     * @param notification 通知オブジェクト
     * @param value        職務経歴書名
     * @return 値オブジェクト
     */
    public static ResumeName create(Notification notification, String value) {
        return new ResumeName(notification, value);
    }

    private void validate(Notification notification, String value) {
        if (isInvalidValue(value)) {
            notification.addError("resumeName", "職務経歴書名には次の文字は使用できません。\n" + "\\ / : * ? \" < > | ");
        }
        if (isInvalidCharStartOrEnd(value)) {
            notification.addError("resumeName", "職務経歴書名の先頭または末尾に「.」を使用することはできません。");
        }
    }

    /**
     * 禁止文字が含まれているかを検証する
     *
     * @param value 職務経歴書名
     * @return 検証結果
     */
    private boolean isInvalidValue(String value) {
        return value.matches(".*" + INVALID_PATTERN + ".*");
    }

    /**
     * 先頭または末尾に使用できない文字が含まれているかを検証する
     *
     * @param value 職務経歴書名
     * @return 検証結果
     */
    private boolean isInvalidCharStartOrEnd(String value) {
        return value.startsWith(INVALID_START_END_CHAR) || value.endsWith(INVALID_START_END_CHAR);
    }
}
