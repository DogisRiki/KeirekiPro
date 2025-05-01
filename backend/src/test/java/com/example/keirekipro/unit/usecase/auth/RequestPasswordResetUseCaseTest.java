package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
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
import com.example.keirekipro.infrastructure.shared.aws.AwsSesClient;
import com.example.keirekipro.infrastructure.shared.mail.FreeMarkerMailTemplate;
import com.example.keirekipro.infrastructure.shared.redis.RedisClient;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.shared.utils.SecurityUtil;
import com.example.keirekipro.usecase.auth.RequestPasswordResetUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class RequestPasswordResetUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private RedisClient redisClient;

    @Mock
    private AwsSesClient awsSesClient;

    @Mock
    private FreeMarkerMailTemplate freeMarkerMailTemplate;

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
        Notification notification = new Notification();
        User user = User.reconstruct(
                USER_ID,
                1,
                Email.create(notification, EMAIL),
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
        when(freeMarkerMailTemplate.create(eq("password-reset.ftl"), anyMap())).thenReturn("テストメール本文");

        // 環境変数をセット
        ReflectionTestUtils.setField(requestPasswordResetUseCase, "frontendBaseUrl", "https://frontend.test");
        ReflectionTestUtils.setField(requestPasswordResetUseCase, "applicationName", "keirekipro");

        // ユースケース実行
        assertThatCode(() -> requestPasswordResetUseCase.execute(EMAIL)).doesNotThrowAnyException();

        // 検証
        verify(userRepository).findByEmail(eq(EMAIL));
        verify(redisClient).setValue("password-reset:" + TOKEN, USER_ID.toString(), Duration.ofMinutes(10));
        verify(freeMarkerMailTemplate).create(eq("password-reset.ftl"), anyMap());
        verify(awsSesClient).sendMail(EMAIL, "【keirekipro】パスワードリセットのご案内", "テストメール本文");
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
        verify(redisClient, never()).setValue(anyString(), anyString(), any());
        verify(freeMarkerMailTemplate, never()).create(anyString(), anyMap());
        verify(awsSesClient, never()).sendMail(anyString(), anyString(), anyString());
    }
}
