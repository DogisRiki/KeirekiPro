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
        assertNotNull(ex.getErrors(), "errorsはnullではない。");
        assertTrue(ex.getErrors().isEmpty(), "errorsは空のMapになっている。");
    }

    @Test
    @DisplayName("コンストラクタを非nullのMapで初期化する")
    void test2() {
        DomainException ex = new DomainException(Map.of("key1", List.of("value1")));
        assertNotNull(ex.getErrors(), "errorsはnullではない。");
        assertFalse(ex.getErrors().isEmpty(), "errorsは空のMapでない。");
        assertEquals(ex.getErrors(), Map.of("key1", List.of("value1")), "errorsの値が初期化時の値と同値である。");
    }

    @Test
    @DisplayName("DomainExceptionをスローする")
    void test3() {
        try {
            throw new DomainException(Map.of("key1", List.of("value1")));
        } catch (DomainException ex) {
            assertTrue(ex instanceof RuntimeException, "DomainExceptionはRuntimeExceptionのサブクラスである。");
            assertEquals(ex.getErrors(), Map.of("key1", List.of("value1")), "errorsの値が初期化時の値と同値である。");
        }
    }
}
