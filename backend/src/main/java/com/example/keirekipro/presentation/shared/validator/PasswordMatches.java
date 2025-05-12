package com.example.keirekipro.presentation.shared.validator;

import static java.lang.annotation.ElementType.TYPE;
import static java.lang.annotation.RetentionPolicy.RUNTIME;

import java.lang.annotation.Documented;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

/**
 * パスワードと確認パスワードが一致しているかを検証するアノテーション
 */
@Target({ TYPE })
@Retention(RUNTIME)
@Constraint(validatedBy = PasswordMatchesValidator.class)
@Documented
public @interface PasswordMatches {

    /**
     * エラーメッセージ
     */
    String message()

    default "パスワードとパスワード(確認)が一致していません。";

    /**
     * バリデーショングループを指定するための属性
     */
    Class<?>[] groups() default {};

    /**
     * カスタムのバリデーションペイロード
     */
    Class<? extends Payload>[] payload() default {};
}
