package com.example.keirekipro.presentation.shared.validator;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

/**
 * LocalDate範囲検証アノテーション
 */
@Documented
@Constraint(validatedBy = LocalDateRangeValidator.class)
@Target({ ElementType.FIELD, ElementType.PARAMETER })
@Retention(RetentionPolicy.RUNTIME)
public @interface LocalDateRange {

    /**
     * エラーメッセージ
     */
    String message() default "日付が不正です。";

    /**
     * バリデーショングループを指定するための属性
     */
    Class<?>[] groups() default {};

    /**
     * カスタムのバリデーションペイロード
     */
    Class<? extends Payload>[] payload() default {};

    /**
     * デフォルト最小値
     */
    int minYear() default 1900;

    /**
     * デフォルト最大値
     */
    int maxYear() default 2100;
}
