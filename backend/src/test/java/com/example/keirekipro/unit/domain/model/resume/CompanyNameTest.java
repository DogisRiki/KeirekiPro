package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class CompanyNameTest {

    @Mock
    private Notification notification;

    @Test
    @DisplayName("有効な値でインスタンス化する")
    void test1() {
        CompanyName companyName = CompanyName.create(notification, "サンプル株式会社");

        assertThat(companyName).isNotNull();
        assertThat(companyName.getValue()).isEqualTo("サンプル株式会社");
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("会社名がnullまたは空白の状態でインスタンス化する")
    void test2() {
        // nullのケース
        {
            reset(notification);
            CompanyName companyName = CompanyName.create(notification, null);

            assertThat(companyName).isNotNull();
            verify(notification, times(1)).addError(
                    eq("companyName"),
                    eq("会社名は入力必須です。"));
        }

        // 空文字のケース
        {
            reset(notification);
            CompanyName companyName = CompanyName.create(notification, "");

            assertThat(companyName).isNotNull();
            verify(notification, times(1)).addError(
                    eq("companyName"),
                    eq("会社名は入力必須です。"));
        }

        // スペースのみのケース
        {
            reset(notification);
            CompanyName companyName = CompanyName.create(notification, "   ");

            assertThat(companyName).isNotNull();
            verify(notification, times(1)).addError(
                    eq("companyName"),
                    eq("会社名は入力必須です。"));
        }

        // タブのみのケース
        {
            reset(notification);
            CompanyName companyName = CompanyName.create(notification, "\t");

            assertThat(companyName).isNotNull();
            verify(notification, times(1)).addError(
                    eq("companyName"),
                    eq("会社名は入力必須です。"));
        }
    }

    @Test
    @DisplayName("会社名が51文字以上の状態でインスタンス化する")
    void test3() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 51; i++) {
            sb.append('a');
        }
        String longName = sb.toString();

        CompanyName companyName = CompanyName.create(notification, longName);

        assertThat(companyName).isNotNull();
        verify(notification, times(1)).addError(
                eq("companyName"),
                eq("会社名は50文字以内で入力してください。"));
    }
}
