package com.example.keirekipro.domain.shared.exception;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class DomainExceptionTest {

    @Test
    @DisplayName("コンストラクタをnullで初期化する")
    void test1() {
        DomainException ex = new DomainException(null);
        // errorsはnullではない。
        assertNotNull(ex.getErrors());
        // errorsは空のMapになっている。
        assertTrue(ex.getErrors().isEmpty());
    }

    @Test
    @DisplayName("コンストラクタを非nullのMapで初期化する")
    void test2() {
        DomainException ex = new DomainException(Map.of("key1", List.of("value1")));
        // errorsはnullではない。
        assertNotNull(ex.getErrors());
        // errorsは空のMapでない。
        assertFalse(ex.getErrors().isEmpty());
        // errorsの値が初期化時の値と同値である。
        assertEquals(ex.getErrors(), Map.of("key1", List.of("value1")));
    }

    @Test
    @DisplayName("DomainExceptionをスローする")
    void test3() {
        try {
            throw new DomainException(Map.of("key1", List.of("value1")));
        } catch (DomainException ex) {
            // DomainExceptionはRuntimeExceptionのサブクラスである。
            assertTrue(ex instanceof RuntimeException);
            // errorsの値が初期化時の値と同値である。
            assertEquals(ex.getErrors(), Map.of("key1", List.of("value1")));
        }
    }
}
