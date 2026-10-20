package com.example.keirekipro.presentation.shared.validator;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

/**
 * 文字列をUTF-8で表したときのバイト数の上限を検証するアノテーション
 */
@Documented
@Constraint(validatedBy = MaxUtf8BytesValidator.class)
@Target({ ElementType.FIELD, ElementType.PARAMETER })
@Retention(RetentionPolicy.RUNTIME)
public @interface MaxUtf8Bytes {

    /**
     * エラーメッセージ
     */
    String message() default "入力が長すぎます。";

    /**
     * バリデーショングループを指定するための属性
     */
    Class<?>[] groups() default {};

    /**
     * カスタムのバリデーションペイロード
     */
    Class<? extends Payload>[] payload() default {};

    /**
     * 許容する最大バイト数
     */
    int value();
}
