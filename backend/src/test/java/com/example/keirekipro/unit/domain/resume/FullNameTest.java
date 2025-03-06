package com.example.keirekipro.unit.domain.resume;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.shared.Notification;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class FullNameTest {

    @Mock
    private Notification notification;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    @DisplayName("有効な値でインスタンス化する")
    void test1() {
        FullName fullName = FullName.create(notification, "Yaま田", "タRoゥ");
        // インスタンスがnullでない。
        assertNotNull(fullName);
        // 姓が正しい値である。
        assertEquals("Yaま田", fullName.getLastName());
        // 名が正しい値である。
        assertEquals("タRoゥ", fullName.getFirstName());
        // notification.addError()が一度も呼ばれていない。
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("姓に不正な値が混入した状態でインスタンス化する")
    void test2() {
        FullName fullName = FullName.create(notification, "@", "太郎");
        // インスタンスがnullでない。
        assertNotNull(fullName);
        // 姓に対するエラーメッセージが登録される。
        verify(notification, times(1)).addError(
                eq("lastName"),
                eq("姓には英数、ひらがな、カタカナ、漢字のみ使用できます。"));
        // 名に対するエラーメッセージが登録されない。
        verify(notification, never()).addError(eq("firstName"), anyString());
    }

    @Test
    @DisplayName("名に不正な値が混入した状態でインスタンス化する")
    void test3() {
        FullName fullName = FullName.create(notification, "山田", "@");
        // インスタンスがnullでない。
        assertNotNull(fullName);
        // 名に対するエラーメッセージが登録される。
        verify(notification, times(
                1)).addError(
                        eq("firstName"),
                        eq("名には英数、ひらがな、カタカナ、漢字のみ使用できます。"));
        // 姓に対するエラーメッセージが登録されない。
        verify(notification, never()).addError(eq("lastName"), anyString());
    }

    @Test
    @DisplayName("姓と名に不正な値が混入した状態でインスタンス化する")
    void test4() {
        FullName fullName = FullName.create(notification, "$", "@");
        // インスタンスがnullでない。
        assertNotNull(fullName);
        // 姓に対するエラーメッセージが登録される。
        verify(notification, times(
                1)).addError(
                        eq("lastName"),
                        eq("姓には英数、ひらがな、カタカナ、漢字のみ使用できます。"));
        // 名に対するエラーメッセージが登録される。
        verify(notification, times(
                1)).addError(
                        eq("firstName"),
                        eq("名には英数、ひらがな、カタカナ、漢字のみ使用できます。"));
    }
}
