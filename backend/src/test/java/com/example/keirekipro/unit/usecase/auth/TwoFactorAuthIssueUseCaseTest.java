package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.util.UUID;

import com.example.keirekipro.infrastructure.shared.aws.AwsSesClient;
import com.example.keirekipro.infrastructure.shared.mail.FreeMarkerMailTemplate;
import com.example.keirekipro.infrastructure.shared.redis.RedisClient;
import com.example.keirekipro.shared.utils.SecurityUtil;
import com.example.keirekipro.usecase.auth.TwoFactorAuthIssueUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class TwoFactorAuthIssueUseCaseTest {

    @Mock
    private RedisClient redisClient;

    @Mock
    private AwsSesClient awsSesClient;

    @Mock
    private FreeMarkerMailTemplate freeMarkerMailTemplate;

    @Mock
    private SecurityUtil securityUtil;

    @InjectMocks
    private TwoFactorAuthIssueUseCase twoFactorAuthIssueUseCase;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";

    @Test
    @DisplayName("2段階認証コードの発行が正しくできる")
    void test1() {
        // モックをセットアップ
        when(securityUtil.generateRandomNumber(6)).thenReturn("012345");
        when(freeMarkerMailTemplate.create(eq("two-factor-auth.ftl"), anyMap())).thenReturn("テストメール本文");
        // テスト用にapplicationNameをセット
        ReflectionTestUtils.setField(twoFactorAuthIssueUseCase, "applicationName", "keirekipro");

        // ユースケース実行
        assertThatCode(() -> {
            twoFactorAuthIssueUseCase.execute(USER_ID, EMAIL);
        }).doesNotThrowAnyException();

        // 検証
        verify(securityUtil).generateRandomNumber(eq(6));
        verify(redisClient).setValue(eq("2fa:" + USER_ID), eq("012345"), eq(Duration.ofMinutes(10)));
        verify(freeMarkerMailTemplate).create(eq("two-factor-auth.ftl"), anyMap());
        verify(awsSesClient).sendMail(eq(EMAIL), eq("【keirekipro】2段階認証コードのお知らせ"), eq("テストメール本文"));
    }
}
