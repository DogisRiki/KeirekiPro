package com.example.keirekipro.presentation.shared.validator;

import java.lang.reflect.Method;

import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

/**
 * PasswordMatchesアノテーションのバリデーター実装
 */
public class PasswordMatchesValidator implements ConstraintValidator<PasswordMatches, Object> {

    @Override
    public boolean isValid(Object value, ConstraintValidatorContext context) {
        try {
            Method getPassword = value.getClass().getMethod("getPassword");
            Method getConfirmPassword = value.getClass().getMethod("getConfirmPassword");

            Object password = getPassword.invoke(value);
            Object confirmPassword = getConfirmPassword.invoke(value);

            if (password == null || confirmPassword == null) {
                return true; // nullチェックは他で行う
            }

            boolean matched = password.equals(confirmPassword);
            if (!matched) {
                context.disableDefaultConstraintViolation();
                context.buildConstraintViolationWithTemplate(context.getDefaultConstraintMessageTemplate())
                        .addPropertyNode("confirmPassword")
                        .addConstraintViolation();
            }

            return matched;
        } catch (Exception e) {
            // メソッドが存在しない、アクセス不可など
            return false;
        }
    }
}
