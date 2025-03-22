package com.example.keirekipro.unit.shared.exception;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import com.example.keirekipro.shared.exception.BaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class BaseExceptionTest {

    private static class TestException extends BaseException {
        public TestException(String message) {
            super(message);
        }

        public TestException(String message, Map<String, List<String>> errors) {
            super(message, errors);
        }
    }

    @Test
    @DisplayName("メッセージのみの場合、errorsは空のマップとなる")
    void test1() {
        String errorMessage = "エラーが発生しました";
        TestException exception = new TestException(errorMessage);

        assertThat(exception.getMessage()).isEqualTo(errorMessage);
        assertThat(exception.getErrors()).isNotNull();
        assertThat(exception.getErrors()).isEmpty();
    }

    @Test
    @DisplayName("メッセージとフィールドエラーの両方を指定した場合、両方とも正しく設定される")
    void test2() {
        String errorMessage = "複合エラーが発生しました";
        Map<String, List<String>> errorMap = new HashMap<>();
        errorMap.put("field1", List.of("フィールド1のエラー"));
        errorMap.put("field2", List.of("フィールド2のエラー"));

        TestException exception = new TestException(errorMessage, errorMap);

        assertThat(exception.getMessage()).isEqualTo(errorMessage);
        assertThat(exception.getErrors()).containsKeys("field1", "field2");
        assertThat(exception.getErrors().get("field1")).contains("フィールド1のエラー");
        assertThat(exception.getErrors().get("field2")).contains("フィールド2のエラー");
    }

    @Test
    @DisplayName("nullフィールドエラーを指定した場合、errorsは空のマップとなる")
    void test3() {
        String errorMessage = "エラーメッセージ";
        TestException exception = new TestException(errorMessage, null);

        assertThat(exception.getMessage()).isEqualTo(errorMessage);
        assertThat(exception.getErrors()).isNotNull();
        assertThat(exception.getErrors()).isEmpty();
    }

    @Test
    @DisplayName("取得したエラーマップは変更不可")
    void test4() {
        TestException exception = new TestException("エラー",
                Map.of("field1", List.of("フィールド1のエラー")));

        // 例外から取得したマップの変更を試みるとUnsupportedOperationExceptionが発生
        assertThatThrownBy(() -> {
            exception.getErrors().put("field2", List.of("新しいエラー"));
        }).isInstanceOf(UnsupportedOperationException.class);
    }

    @Test
    @DisplayName("エラーマップの各要素へのアクセスが可能")
    void test5() {
        Map<String, List<String>> errorMap = Map.of(
                "field1", List.of("エラー1-1", "エラー1-2"),
                "field2", List.of("エラー2-1"));

        TestException exception = new TestException("複合エラー", errorMap);

        assertThat(exception.getErrors().size()).isEqualTo(2);
        assertThat(exception.getErrors().get("field1")).hasSize(2);
        assertThat(exception.getErrors().get("field1")).containsExactly("エラー1-1", "エラー1-2");
        assertThat(exception.getErrors().get("field2")).hasSize(1);
        assertThat(exception.getErrors().get("field2")).containsExactly("エラー2-1");
    }
}
