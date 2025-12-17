package com.example.keirekipro.presentation.shared.validator;

import java.time.LocalDate;

import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

/**
 * LocalDateRangeアノテーションのバリデーター実装
 */
public class LocalDateRangeValidator implements ConstraintValidator<LocalDateRange, LocalDate> {

    private int minYear;
    private int maxYear;

    @Override
    public void initialize(LocalDateRange annotation) {
        this.minYear = annotation.minYear();
        this.maxYear = annotation.maxYear();
    }

    @Override
    public boolean isValid(LocalDate value, ConstraintValidatorContext context) {
        if (value == null) {
            return true; // 必須チェックは @NotNull に委譲
        }
        int y = value.getYear();
        return y >= minYear && y <= maxYear;
    }
}
