package com.example.keirekipro.domain.shared;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class NotificationTest {

    @Test
    @DisplayName("インスタンス化した直後はエラーが1つも存在しないこと")
    void test1() {
        Notification notification = new Notification();
        assertFalse(notification.hasErrors());
    }

    @Test
    @DisplayName("単一のエラーを追加する")
    void test2() {
        Notification notification = new Notification();
        notification.addError("field", "エラーメッセージ");
        assertTrue(notification.hasErrors());
        assertEquals(notification.getErrors(), Map.of("field", List.of("エラーメッセージ")));
    }

    @Test
    @DisplayName("同一フィールド名に複数のエラーを追加する")
    void test3() {
        Notification notification = new Notification();
        notification.addError("field", "エラーメッセージ1");
        notification.addError("field", "エラーメッセージ2");
        assertTrue(notification.hasErrors());
        assertEquals(notification.getErrors(), Map.of("field", List.of("エラーメッセージ1", "エラーメッセージ2")));
    }

    @Test
    @DisplayName("複数のフィールド名にの複数のエラーを追加する")
    void test4() {
        Notification notification = new Notification();
        notification.addError("field1", "エラーメッセージ1-1");
        notification.addError("field1", "エラーメッセージ1-2");
        notification.addError("field2", "エラーメッセージ2-1");
        notification.addError("field2", "エラーメッセージ2-2");
        assertTrue(notification.hasErrors());
        assertEquals(notification.getErrors(),
                Map.of("field1", List.of("エラーメッセージ1-1", "エラーメッセージ1-2"), "field2",
                        List.of("エラーメッセージ2-1", "エラーメッセージ2-2")));
    }

}
