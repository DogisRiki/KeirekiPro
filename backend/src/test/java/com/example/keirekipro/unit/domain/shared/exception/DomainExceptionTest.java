package com.example.keirekipro.unit.domain.shared.exception;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;

import com.example.keirekipro.domain.shared.exception.DomainException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class DomainExceptionTest {

    @Test
    @DisplayName("コンストラクタをnullで初期化する")
    void test1() {
        DomainException ex = new DomainException(null);

        assertThat(ex.getErrors())
                .isNotNull()
                .isEmpty();
    }

    @Test
    @DisplayName("コンストラクタを非nullのMapで初期化する")
    void test2() {
        DomainException ex = new DomainException(Map.of("key1", List.of("value1")));

        assertThat(ex.getErrors())
                .isNotNull()
                .isNotEmpty()
                .isEqualTo(Map.of("key1", List.of("value1")));
    }

    @Test
    @DisplayName("DomainExceptionをスローする")
    void test3() {
        try {
            throw new DomainException(Map.of("key1", List.of("value1")));
        } catch (DomainException ex) {
            assertThat(ex)
                    .isInstanceOf(RuntimeException.class);
            assertThat(ex.getErrors())
                    .isEqualTo(Map.of("key1", List.of("value1")));
        }
    }
}
