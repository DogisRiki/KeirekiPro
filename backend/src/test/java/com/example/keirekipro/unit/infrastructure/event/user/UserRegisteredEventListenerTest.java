package com.example.keirekipro.unit.infrastructure.event.user;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Map;
import java.util.UUID;

import com.example.keirekipro.domain.event.user.UserRegisteredEvent;
import com.example.keirekipro.infrastructure.event.user.UserRegisteredEventListener;
import com.example.keirekipro.infrastructure.shared.aws.AwsSesClient;
import com.example.keirekipro.infrastructure.shared.mail.FreeMarkerMailTemplate;
import com.example.keirekipro.shared.config.AppProperties;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserRegisteredEventListenerTest {

    @Mock
    private AwsSesClient awsSesClient;

    @Mock
    private FreeMarkerMailTemplate freeMarkerMailTemplate;

    @Mock
    private AppProperties properties;

    @InjectMocks
    private UserRegisteredEventListener listener;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "registered-user";

    @Test
    @DisplayName("ユーザー新規登録イベントを受け取り、新規登録メールを送信する")
    void test1() {
        // モックをセットアップ
        when(properties.getSiteName()).thenReturn("KeirekiPro");
        when(properties.getSiteUrl()).thenReturn("https://keirekipro.click");

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        doReturn("新規登録メール本文")
                .when(freeMarkerMailTemplate)
                .create(eq("user-registered.ftl"), captor.capture());

        // イベント生成
        UserRegisteredEvent event = new UserRegisteredEvent(USER_ID, EMAIL, USERNAME);

        // 実行
        assertThatCode(() -> listener.handle(event)).doesNotThrowAnyException();

        // 検証
        verify(freeMarkerMailTemplate).create(eq("user-registered.ftl"), anyMap());
        verify(awsSesClient).sendMail(EMAIL, "【KeirekiPro】新規登録完了のお知らせ", "新規登録メール本文");

        // テンプレートデータの内容確認
        Map<String, Object> capturedMap = captor.getValue();
        assert capturedMap.get("username").equals(USERNAME);
        assert capturedMap.get("siteName").equals("KeirekiPro");
        assert capturedMap.get("siteUrl").equals("https://keirekipro.click");
    }
}
