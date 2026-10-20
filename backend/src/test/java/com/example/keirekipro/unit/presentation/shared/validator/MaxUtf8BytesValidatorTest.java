package com.example.keirekipro.unit.presentation.shared.validator;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.keirekipro.presentation.shared.validator.MaxUtf8Bytes;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;

class MaxUtf8BytesValidatorTest {

    private static ValidatorFactory factory;
    private static Validator validator;

    @BeforeAll
    static void setUp() {
        factory = Validation.buildDefaultValidatorFactory();
        validator = factory.getValidator();
    }

    @AfterAll
    static void tearDown() {
        factory.close();
    }

    private record Target(@MaxUtf8Bytes(value = 72, message = "長すぎます。") String value) {
    }

    @Test
    @DisplayName("半角72文字(72バイト)は受け付ける")
    void test1() {
        assertThat(validator.validate(new Target("a".repeat(72)))).isEmpty();
    }

    @Test
    @DisplayName("半角73文字(73バイト)は受け付けない")
    void test2() {
        var violations = validator.validate(new Target("a".repeat(73)));
        assertThat(violations).hasSize(1);
        assertThat(violations.iterator().next().getMessage()).isEqualTo("長すぎます。");
    }

    @Test
    @DisplayName("全角24文字(72バイト)は受け付ける")
    void test3() {
        assertThat(validator.validate(new Target("あ".repeat(24)))).isEmpty();
    }

    @Test
    @DisplayName("全角25文字(75バイト)は、文字数が少なくても受け付けない")
    void test4() {
        assertThat(validator.validate(new Target("あ".repeat(25)))).hasSize(1);
    }

    @Test
    @DisplayName("nullは受け付ける")
    void test5() {
        assertThat(validator.validate(new Target(null))).isEmpty();
    }
}
