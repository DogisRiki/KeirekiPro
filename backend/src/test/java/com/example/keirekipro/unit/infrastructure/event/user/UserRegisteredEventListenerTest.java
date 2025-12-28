package com.example.keirekipro.unit.infrastructure.event.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.UUID;

import com.example.keirekipro.domain.event.user.UserRegisteredEvent;
import com.example.keirekipro.infrastructure.event.user.UserRegisteredEventListener;
import com.example.keirekipro.shared.config.AppProperties;
import com.example.keirekipro.usecase.shared.notification.NotificationDispatcher;
import com.example.keirekipro.usecase.user.notification.UserRegisteredNotification;

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
    private NotificationDispatcher notificationDispatcher;

    @Mock
    private AppProperties properties;

    @InjectMocks
    private UserRegisteredEventListener listener;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "registered-user";

    @Test
    @DisplayName("ユーザー新規登録イベントを受け取り、新規登録通知を送達する")
    void test1() {
        // モックをセットアップ
        when(properties.getSiteName()).thenReturn("KeirekiPro");
        when(properties.getSiteUrl()).thenReturn("https://keirekipro.click");

        // イベント生成
        UserRegisteredEvent event = new UserRegisteredEvent(USER_ID, EMAIL, USERNAME);

        // 実行
        assertThatCode(() -> listener.handle(event)).doesNotThrowAnyException();

        // dispatch引数の検証に使用するキャプチャを作成
        ArgumentCaptor<UserRegisteredNotification> captor = ArgumentCaptor.forClass(UserRegisteredNotification.class);

        // 検証
        verify(notificationDispatcher).dispatch(captor.capture());

        UserRegisteredNotification notification = captor.getValue();
        assertThat(notification.to()).isEqualTo(EMAIL);
        assertThat(notification.username()).isEqualTo(USERNAME);
        assertThat(notification.siteName()).isEqualTo("KeirekiPro");
        assertThat(notification.siteUrl()).isEqualTo("https://keirekipro.click");
    }
}
