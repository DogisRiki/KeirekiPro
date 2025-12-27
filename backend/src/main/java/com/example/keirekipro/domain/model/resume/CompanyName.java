package com.example.keirekipro.domain.model.resume;

import com.example.keirekipro.shared.ErrorCollector;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * 会社名
 */
@Getter
@EqualsAndHashCode
public class CompanyName {

    private final String value;

    private CompanyName(ErrorCollector errorCollector, String value) {
        validate(errorCollector, value);
        this.value = value;
    }

    /**
     * ファクトリーメソッド
     *
     * @param errorCollector エラー収集オブジェクト
     * @param value          会社名
     * @return 値オブジェクト
     */
    public static CompanyName create(ErrorCollector errorCollector, String value) {
        return new CompanyName(errorCollector, value);
    }

    private void validate(ErrorCollector errorCollector, String value) {
        if (value == null || value.isBlank()) {
            errorCollector.addError("companyName", "会社名は入力必須です。");
            return;
        }
        if (value.length() > 50) {
            errorCollector.addError("companyName", "会社名は50文字以内で入力してください。");
        }
    }
}
