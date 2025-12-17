package com.example.keirekipro.presentation.shared.validator;

import java.time.YearMonth;

import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

/**
 * YearMonthRangeアノテーションのバリデーター実装
 */
public class YearMonthRangeValidator implements ConstraintValidator<YearMonthRange, YearMonth> {

    private int minYear;
    private int maxYear;

    @Override
    public void initialize(YearMonthRange annotation) {
        this.minYear = annotation.minYear();
        this.maxYear = annotation.maxYear();
    }

    @Override
    public boolean isValid(YearMonth value, ConstraintValidatorContext context) {
        if (value == null) {
            return true; // 必須チェックは @NotNull に委譲
        }
        int y = value.getYear();
        return y >= minYear && y <= maxYear;
    }
}
