package com.example.keirekipro.unit.domain.model.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import java.util.Arrays;
import java.util.List;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.shared.ErrorCollector;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class EmailTest {

    @Mock
    private ErrorCollector errorCollector;

    @Test
    @DisplayName("有効な値でインスタンス化する")
    void test1() {
        String validMail = "test-user@example.com";
        Email email = Email.create(errorCollector, validMail);

        assertThat(email).isNotNull();
        assertThat(email.getValue()).isEqualTo(validMail);
        verify(errorCollector, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("メールアドレスが空の場合にエラーが登録される")
    void test2() {
        List<String> testValues = Arrays.asList("", "  ", null);

        for (String value : testValues) {
            // 毎回モックをリセットして、呼び出し履歴をクリアする
            reset(errorCollector);
            Email email = Email.create(errorCollector, value);

            assertThat(email).isNotNull();
            // メールアドレスに対するエラーメッセージが登録される
            verify(errorCollector, times(1)).addError(
                    eq("email"),
                    eq("メールアドレスが空です。"));
        }
    }

    @Test
    @DisplayName("無効な形式のメールアドレスの場合にエラーが登録される")
    void test3() {
        List<String> invalidValues = List.of(
                "test-user@",
                "test-user",
                "example.com",
                "ああああ",
                "foo@@example.com");

        for (String value : invalidValues) {
            reset(errorCollector);
            Email email = Email.create(errorCollector, value);

            assertThat(email).isNotNull();
            // メールアドレスに対するエラーメッセージが登録される
            verify(errorCollector, times(1)).addError(
                    eq("email"),
                    eq("メールアドレスの形式が不正です。"));
        }
    }
}
