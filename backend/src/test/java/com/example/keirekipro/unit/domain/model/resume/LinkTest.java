package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import java.util.List;

import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class LinkTest {

    @Mock
    private Notification notification;

    @Test
    @DisplayName("有効な値でインスタンス化する")
    void test1() {
        Link link = Link.create(notification, "https://example.com");

        assertThat(link).isNotNull();
        assertThat(link.getValue()).isEqualTo("https://example.com");
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("不正なURL形式でインスタンス化する")
    void test2() {
        List<String> testValues = List.of("http://example.com", "ftp://example.com", "invalid-uri");
        for (String value : testValues) {
            // 毎回モックをリセットして、呼び出し履歴をクリアする
            reset(notification);
            Link link = Link.create(notification, value);

            assertThat(link).isNotNull();
            // リンクに対するエラーメッセージが登録される
            verify(notification, times(1)).addError(
                    eq("link"),
                    eq("無効なURLです。HTTPS形式で正しいURLを入力してください。"));
        }
    }

    @Test
    @DisplayName("リンクがnullまたは空白の状態でインスタンス化する")
    void test3() {
        // nullのケース
        {
            reset(notification);
            Link link = Link.create(notification, null);

            assertThat(link).isNotNull();
            verify(notification, times(1)).addError(
                    eq("link"),
                    eq("リンクは入力必須です。"));
            verify(notification, never()).addError(
                    eq("link"),
                    eq("無効なURLです。HTTPS形式で正しいURLを入力してください。"));
        }

        // 空文字のケース
        {
            reset(notification);
            Link link = Link.create(notification, "");

            assertThat(link).isNotNull();
            verify(notification, times(1)).addError(
                    eq("link"),
                    eq("リンクは入力必須です。"));
            verify(notification, never()).addError(
                    eq("link"),
                    eq("無効なURLです。HTTPS形式で正しいURLを入力してください。"));
        }

        // スペースのみのケース
        {
            reset(notification);
            Link link = Link.create(notification, "   ");

            assertThat(link).isNotNull();
            verify(notification, times(1)).addError(
                    eq("link"),
                    eq("リンクは入力必須です。"));
            verify(notification, never()).addError(
                    eq("link"),
                    eq("無効なURLです。HTTPS形式で正しいURLを入力してください。"));
        }

        // タブのみのケース
        {
            reset(notification);
            Link link = Link.create(notification, "\t");

            assertThat(link).isNotNull();
            verify(notification, times(1)).addError(
                    eq("link"),
                    eq("リンクは入力必須です。"));
            verify(notification, never()).addError(
                    eq("link"),
                    eq("無効なURLです。HTTPS形式で正しいURLを入力してください。"));
        }
    }
}
