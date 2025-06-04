package com.example.keirekipro.unit.infrastructure.event.user;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Map;
import java.util.UUID;

import com.example.keirekipro.domain.event.user.UserDeletedEvent;
import com.example.keirekipro.infrastructure.event.user.UserDeletedEventListener;
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
class UserDeletedEventListenerTest {

    @Mock
    private AwsSesClient awsSesClient;

    @Mock
    private FreeMarkerMailTemplate freeMarkerMailTemplate;

    @Mock
    private AppProperties properties;

    @InjectMocks
    private UserDeletedEventListener listener;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "deleted-user";

    @Test
    @DisplayName("ユーザー削除イベントを受け取り、退会メールを送信する")
    void test1() {
        // モックをセットアップ
        when(properties.getSiteName()).thenReturn("KeirekiPro");
        when(properties.getSiteUrl()).thenReturn("https://keirekipro.click");

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        doReturn("退会メール本文")
                .when(freeMarkerMailTemplate)
                .create(eq("user-deleted.ftl"), captor.capture());

        // イベント生成
        UserDeletedEvent event = new UserDeletedEvent(USER_ID, EMAIL, USERNAME);

        // 実行
        assertThatCode(() -> listener.handle(event)).doesNotThrowAnyException();

        // 検証
        verify(freeMarkerMailTemplate).create(eq("user-deleted.ftl"), anyMap());
        verify(awsSesClient).sendMail(EMAIL, "【KeirekiPro】退会手続き完了のお知らせ", "退会メール本文");

        // テンプレートデータの内容確認
        Map<String, Object> capturedMap = captor.getValue();
        assert capturedMap.get("username").equals(USERNAME);
        assert capturedMap.get("siteName").equals("KeirekiPro");
        assert capturedMap.get("siteUrl").equals("https://keirekipro.click");
    }
}
