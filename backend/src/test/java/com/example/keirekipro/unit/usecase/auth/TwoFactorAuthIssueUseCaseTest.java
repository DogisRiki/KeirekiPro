package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.util.UUID;

import com.example.keirekipro.shared.config.AppProperties;
import com.example.keirekipro.shared.utils.SecurityUtil;
import com.example.keirekipro.usecase.auth.TwoFactorAuthIssueUseCase;
import com.example.keirekipro.usecase.auth.notification.TwoFactorCodeNotification;
import com.example.keirekipro.usecase.auth.store.TwoFactorAuthCodeStore;
import com.example.keirekipro.usecase.shared.notification.NotificationDispatcher;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class TwoFactorAuthIssueUseCaseTest {

    @Mock
    private TwoFactorAuthCodeStore twoFactorAuthCodeStore;

    @Mock
    private NotificationDispatcher notificationDispatcher;

    @Mock
    private SecurityUtil securityUtil;

    @Mock
    private AppProperties properties;

    @InjectMocks
    private TwoFactorAuthIssueUseCase twoFactorAuthIssueUseCase;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";

    @Test
    @DisplayName("2段階認証コードの発行が正しくできる")
    void test1() {
        // モックのセットアップ
        when(securityUtil.generateRandomNumber(6)).thenReturn("012345");
        when(properties.getSiteName()).thenReturn("KeirekiPro");
        when(properties.getSiteUrl()).thenReturn("https://keirekipro.click");

        // 実行
        assertThatCode(() -> {
            twoFactorAuthIssueUseCase.execute(USER_ID, EMAIL);
        }).doesNotThrowAnyException();

        // 検証
        verify(securityUtil).generateRandomNumber(eq(6));
        verify(twoFactorAuthCodeStore).store(eq(USER_ID), eq("012345"), eq(Duration.ofMinutes(10)));

        // 通知内容の検証
        ArgumentCaptor<TwoFactorCodeNotification> captor = ArgumentCaptor.forClass(TwoFactorCodeNotification.class);
        verify(notificationDispatcher).dispatch(captor.capture());

        TwoFactorCodeNotification notification = captor.getValue();
        assertThat(notification.to()).isEqualTo(EMAIL);
        assertThat(notification.code()).isEqualTo("012345");
        assertThat(notification.siteName()).isEqualTo("KeirekiPro");
        assertThat(notification.siteUrl()).isEqualTo("https://keirekipro.click");
    }
}
