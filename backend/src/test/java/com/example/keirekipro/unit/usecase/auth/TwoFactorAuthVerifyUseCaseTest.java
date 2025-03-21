package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.shared.redis.RedisClient;
import com.example.keirekipro.usecase.auth.TwoFactorAuthVerifyUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.BadCredentialsException;

@ExtendWith(MockitoExtension.class)
class TwoFactorAuthVerifyUseCaseTest {

    @Mock
    private RedisClient redisClient;

    @InjectMocks
    private TwoFactorAuthVerifyUseCase twoFactorAuthVerifyUseCase;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String CODE = "012345";

    @Test
    @DisplayName("2段階認証コードの検証がOK")
    void test1() {
        // モックをセットアップ
        when(redisClient.getValue("2fa:" + USER_ID, String.class)).thenReturn(Optional.of(CODE));

        // ユースケース実行
        assertThatCode(() -> {
            twoFactorAuthVerifyUseCase.execute(USER_ID, CODE);
        }).doesNotThrowAnyException();

        // 検証
        verify(redisClient).deleteValue(eq("2fa:" + USER_ID));
    }

    @Test
    @DisplayName("2段階認証コードが期限切れの場合、BadCredentialsExceptionがスローされる")
    void test2() {
        // モックをセットアップ
        when(redisClient.getValue("2fa:" + USER_ID, String.class)).thenReturn(Optional.empty());

        // ユースケース実行
        assertThatThrownBy(() -> {
            twoFactorAuthVerifyUseCase.execute(USER_ID, CODE);
        })
                .isInstanceOf(BadCredentialsException.class)
                .hasMessage("二段階認証コードが期限切れです。再度認証を行ってください。");

        // 検証
        verify(redisClient, never()).deleteValue(anyString());
    }

    @Test
    @DisplayName("2段階認証コードの検証がNGの場合、BadCredentialsExceptionがスローされる")
    void test3() {
        // モックをセットアップ
        when(redisClient.getValue("2fa:" + USER_ID, String.class)).thenReturn(Optional.of(CODE));

        // ユースケース実行
        assertThatThrownBy(() -> {
            twoFactorAuthVerifyUseCase.execute(USER_ID, "999999");
        })
                .isInstanceOf(BadCredentialsException.class)
                .hasMessage("二段階認証コードが正しくありません。");

        // 検証
        verify(redisClient, never()).deleteValue(anyString());
    }
}
