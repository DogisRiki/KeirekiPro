package com.example.keirekipro.domain.model.resume;

import com.example.keirekipro.shared.ErrorCollector;

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

    private ResumeName(ErrorCollector errorCollector, String value) {
        validate(errorCollector, value);
        this.value = value;
    }

    /**
     * ファクトリーメソッド
     *
     * @param errorCollector エラー収集オブジェクト
     * @param value          職務経歴書名
     * @return 値オブジェクト
     */
    public static ResumeName create(ErrorCollector errorCollector, String value) {
        return new ResumeName(errorCollector, value);
    }

    private void validate(ErrorCollector errorCollector, String value) {
        if (value == null || value.isBlank()) {
            errorCollector.addError("resumeName", "職務経歴書名は入力必須です。");
            return;
        }
        if (value.length() > 50) {
            errorCollector.addError("resumeName", "職務経歴書名は50文字以内で入力してください。");
        }
        if (isInvalidValue(value)) {
            errorCollector.addError("resumeName", "職務経歴書名には次の文字は使用できません。\n" + "\\ / : * ? \" < > | ");
        }
        if (isInvalidCharStartOrEnd(value)) {
            errorCollector.addError("resumeName", "職務経歴書名の先頭または末尾に「.」を使用することはできません。");
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
