package com.example.keirekipro.domain.model.resume;

import com.example.keirekipro.shared.ErrorCollector;

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

    private FullName(ErrorCollector errorCollector, String lastName, String firstName) {
        validate(errorCollector, lastName, firstName);
        this.lastName = lastName;
        this.firstName = firstName;
    }

    /**
     * ファクトリーメソッド
     *
     * @param errorCollector エラー収集オブジェクト
     * @param lastName       姓
     * @param firstName      名
     * @return 値オブジェクト
     */
    public static FullName create(ErrorCollector errorCollector, String lastName, String firstName) {
        return new FullName(errorCollector, lastName, firstName);
    }

    private void validate(ErrorCollector errorCollector, String lastName, String firstName) {
        if (lastName == null || lastName.isBlank()) {
            errorCollector.addError("lastName", "姓は入力必須です。");
        } else {
            if (lastName.length() > 10) {
                errorCollector.addError("lastName", "姓は10文字以内で入力してください。");
            }
            if (isInvalidValue(lastName)) {
                errorCollector.addError("lastName", "姓には英数、ひらがな、カタカナ、漢字のみ使用できます。");
            }
        }
        if (firstName == null || firstName.isBlank()) {
            errorCollector.addError("firstName", "名は入力必須です。");
        } else {
            if (firstName.length() > 10) {
                errorCollector.addError("firstName", "名は10文字以内で入力してください。");
            }
            if (isInvalidValue(firstName)) {
                errorCollector.addError("firstName", "名には英数、ひらがな、カタカナ、漢字のみ使用できます。");
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
