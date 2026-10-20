package com.example.keirekipro.presentation.shared.validator;

import java.nio.charset.StandardCharsets;

import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

/**
 * MaxUtf8Bytesアノテーションのバリデーター実装
 */
public class MaxUtf8BytesValidator implements ConstraintValidator<MaxUtf8Bytes, CharSequence> {

    private int max;

    @Override
    public void initialize(MaxUtf8Bytes constraintAnnotation) {
        this.max = constraintAnnotation.value();
    }

    @Override
    public boolean isValid(CharSequence value, ConstraintValidatorContext context) {
        if (value == null) {
            return true; // nullチェックは他で行う
        }
        return value.toString().getBytes(StandardCharsets.UTF_8).length <= max;
    }
}
