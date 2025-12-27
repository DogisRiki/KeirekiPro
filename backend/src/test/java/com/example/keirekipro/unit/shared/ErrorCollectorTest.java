package com.example.keirekipro.unit.shared;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;

import com.example.keirekipro.shared.ErrorCollector;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class ErrorCollectorTest {

    @Test
    @DisplayName("インスタンス化した直後はエラーが1つも存在しないこと")
    void test1() {
        ErrorCollector errorCollector = new ErrorCollector();

        assertThat(errorCollector.hasErrors())
                .isFalse();
    }

    @Test
    @DisplayName("単一のエラーを追加する")
    void test2() {
        ErrorCollector errorCollector = new ErrorCollector();
        errorCollector.addError("field", "エラーメッセージ");

        assertThat(errorCollector.hasErrors())
                .isTrue();
        assertThat(errorCollector.getErrors())
                .isEqualTo(Map.of("field", List.of("エラーメッセージ")));
    }

    @Test
    @DisplayName("同一フィールド名に複数のエラーを追加する")
    void test3() {
        ErrorCollector errorCollector = new ErrorCollector();
        errorCollector.addError("field", "エラーメッセージ1");
        errorCollector.addError("field", "エラーメッセージ2");

        assertThat(errorCollector.hasErrors())
                .isTrue();
        assertThat(errorCollector.getErrors())
                .isEqualTo(Map.of("field", List.of("エラーメッセージ1", "エラーメッセージ2")));
    }

    @Test
    @DisplayName("複数のフィールド名にの複数のエラーを追加する")
    void test4() {
        ErrorCollector errorCollector = new ErrorCollector();
        errorCollector.addError("field1", "エラーメッセージ1-1");
        errorCollector.addError("field1", "エラーメッセージ1-2");
        errorCollector.addError("field2", "エラーメッセージ2-1");
        errorCollector.addError("field2", "エラーメッセージ2-2");

        assertThat(errorCollector.hasErrors())
                .isTrue();
        assertThat(errorCollector.getErrors())
                .isEqualTo(Map.of(
                        "field1", List.of("エラーメッセージ1-1", "エラーメッセージ1-2"),
                        "field2", List.of("エラーメッセージ2-1", "エラーメッセージ2-2")));
    }
}
