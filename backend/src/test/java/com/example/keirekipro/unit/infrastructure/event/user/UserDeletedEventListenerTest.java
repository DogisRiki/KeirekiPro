package com.example.keirekipro.unit.infrastructure.event.user;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.UUID;

import com.example.keirekipro.domain.event.user.UserDeletedEvent;
import com.example.keirekipro.infrastructure.event.user.UserDeletedEventListener;
import com.example.keirekipro.infrastructure.shared.aws.AwsSesClient;
import com.example.keirekipro.infrastructure.shared.mail.FreeMarkerMailTemplate;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class UserDeletedEventListenerTest {

    @Mock
    private AwsSesClient awsSesClient;

    @Mock
    private FreeMarkerMailTemplate freeMarkerMailTemplate;

    @InjectMocks
    private UserDeletedEventListener listener;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "deleted-user";

    @Test
    @DisplayName("ユーザー削除イベントを受け取り、退会メールを送信する")
    void test1() {
        // モックをセットアップ
        when(freeMarkerMailTemplate.create(eq("user-deleted.ftl"), anyMap())).thenReturn("退会メール本文");
        // テスト用にapplicationNameをセット
        ReflectionTestUtils.setField(listener, "applicationName", "keirekipro");

        // イベント生成
        UserDeletedEvent event = new UserDeletedEvent(USER_ID, EMAIL, USERNAME);

        // 実行 & 検証
        assertThatCode(() -> listener.handle(event)).doesNotThrowAnyException();
        verify(freeMarkerMailTemplate).create(eq("user-deleted.ftl"), anyMap());
        verify(awsSesClient).sendMail(eq(EMAIL), eq("【keirekipro】退会手続きが完了しました"), eq("退会メール本文"));
    }
}
