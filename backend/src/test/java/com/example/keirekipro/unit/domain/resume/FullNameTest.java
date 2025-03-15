package com.example.keirekipro.unit.domain.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class FullNameTest {

    @Mock
    private Notification notification;

    @Test
    @DisplayName("有効な値でインスタンス化する")
    void test1() {
        FullName fullName = FullName.create(notification, "Yaま田", "タRoゥ");

        assertThat(fullName).isNotNull();
        assertThat(fullName.getLastName()).isEqualTo("Yaま田");
        assertThat(fullName.getFirstName()).isEqualTo("タRoゥ");
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("姓に不正な値が混入した状態でインスタンス化する")
    void test2() {
        FullName fullName = FullName.create(notification, "@", "太郎");

        assertThat(fullName).isNotNull();
        // 姓に対するエラーメッセージが登録される
        verify(notification, times(1)).addError(
                eq("lastName"),
                eq("姓には英数、ひらがな、カタカナ、漢字のみ使用できます。"));
        // 名に対するエラーメッセージは登録されない
        verify(notification, never()).addError(eq("firstName"), anyString());
    }

    @Test
    @DisplayName("名に不正な値が混入した状態でインスタンス化する")
    void test3() {
        FullName fullName = FullName.create(notification, "山田", "@");

        assertThat(fullName).isNotNull();
        // 名に対するエラーメッセージが登録される
        verify(notification, times(1)).addError(
                eq("firstName"),
                eq("名には英数、ひらがな、カタカナ、漢字のみ使用できます。"));
        // 姓に対するエラーメッセージは登録されない
        verify(notification, never()).addError(eq("lastName"), anyString());
    }

    @Test
    @DisplayName("姓と名に不正な値が混入した状態でインスタンス化する")
    void test4() {
        FullName fullName = FullName.create(notification, "$", "@");

        assertThat(fullName).isNotNull();
        // 姓に対するエラーメッセージが登録される
        verify(notification, times(1)).addError(
                eq("lastName"),
                eq("姓には英数、ひらがな、カタカナ、漢字のみ使用できます。"));
        // 名に対するエラーメッセージが登録される
        verify(notification, times(1)).addError(
                eq("firstName"),
                eq("名には英数、ひらがな、カタカナ、漢字のみ使用できます。"));
    }
}
