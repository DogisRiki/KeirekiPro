package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.shared.utils.SecurityUtil;
import com.example.keirekipro.usecase.auth.RequestPasswordResetUseCase;
import com.example.keirekipro.usecase.auth.notification.PasswordResetNotification;
import com.example.keirekipro.usecase.auth.store.PasswordResetTokenStore;
import com.example.keirekipro.usecase.shared.notification.NotificationDispatcher;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class RequestPasswordResetUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordResetTokenStore passwordResetTokenStore;

    @Mock
    private NotificationDispatcher notificationDispatcher;

    @Mock
    private SecurityUtil securityUtil;

    @InjectMocks
    private RequestPasswordResetUseCase requestPasswordResetUseCase;

    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final UUID USER_ID = UUID.randomUUID();
    private static final String TOKEN = "mock-token";

    @Test
    @DisplayName("パスワードリセット要求が正常に行われる")
    void test1() {
        // データ準備
        ErrorCollector errorCollector = new ErrorCollector();
        User user = User.reconstruct(
                USER_ID,
                Email.create(errorCollector, EMAIL),
                "hashedPassword",
                false,
                null,
                null,
                USERNAME,
                null,
                null);

        // モックセットアップ
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(securityUtil.generateRandomToken()).thenReturn(TOKEN);

        // 環境変数をセット
        ReflectionTestUtils.setField(requestPasswordResetUseCase, "frontendBaseUrl", "https://frontend.test");
        ReflectionTestUtils.setField(requestPasswordResetUseCase, "applicationName", "keirekipro");

        // ユースケース実行
        assertThatCode(() -> requestPasswordResetUseCase.execute(EMAIL)).doesNotThrowAnyException();

        // 検証
        verify(userRepository).findByEmail(eq(EMAIL));
        verify(passwordResetTokenStore).store(eq(TOKEN), eq(USER_ID), eq(Duration.ofMinutes(10)));

        // 通知内容の検証
        ArgumentCaptor<PasswordResetNotification> captor = ArgumentCaptor.forClass(PasswordResetNotification.class);
        verify(notificationDispatcher).dispatch(captor.capture());

        PasswordResetNotification notification = captor.getValue();
        assertThat(notification.to()).isEqualTo(EMAIL);
        assertThat(notification.resetLink()).isEqualTo("https://frontend.test/password/reset/" + TOKEN);
        assertThat(notification.siteName()).isEqualTo("keirekipro");
        assertThat(notification.siteUrl()).isEqualTo("https://frontend.test");
    }

    @Test
    @DisplayName("存在しないメールアドレスでもエラーにならない（メールを送らない）")
    void test2() {
        // モックセットアップ
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());

        // ユースケース実行
        assertThatCode(() -> requestPasswordResetUseCase.execute(EMAIL)).doesNotThrowAnyException();

        // 検証
        verify(securityUtil, never()).generateRandomToken();
        verify(passwordResetTokenStore, never()).store(anyString(), any(), any());
        verify(notificationDispatcher, never()).dispatch(any());
    }
}
