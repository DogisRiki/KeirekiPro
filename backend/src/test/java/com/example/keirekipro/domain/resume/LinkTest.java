package com.example.keirekipro.domain.resume;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import java.util.List;

import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.shared.Notification;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class LinkTest {

    @Mock
    private Notification notification;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    @DisplayName("有効な値でインスタンス化する")
    void test1() {
        Link link = Link.create(notification, "https://example.com");
        // インスタンスがnullでない。
        assertNotNull(link);
        // 職務経歴書名が正しい値である。
        assertEquals(link.getValue(), "https://example.com");
        // notification.addError()が一度も呼ばれていない。
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("不正な値でインスタンス化する")
    void test2() {
        List<String> testValues = List.of("http://example.com", "ftp://example.com", "invalid-uri", "");
        for (String value : testValues) {
            // 毎回モックをリセットして、呼び出し履歴をクリアする
            reset(notification);
            Link link = Link.create(notification, value);
            // インスタンスがnullでない。
            assertNotNull(link);
            // リンクに対するエラーメッセージが登録される
            verify(notification, times(1)).addError(
                    eq("link"),
                    eq("無効なURLです。HTTPS形式で正しいURLを入力してください。"));
        }
    }
}
