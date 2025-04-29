package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.shared.redis.RedisClient;
import com.example.keirekipro.usecase.auth.VerifyPasswordResetTokenUseCase;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class VerifyPasswordResetTokenUseCaseTest {

    @Mock
    private RedisClient redisClient;

    @InjectMocks
    private VerifyPasswordResetTokenUseCase verifyPasswordResetTokenUseCase;

    private static final String TOKEN = "mock-token";
    private static final UUID USER_ID = UUID.randomUUID();

    @Test
    @DisplayName("リセットトークンの検証が成功する")
    void test1() {
        // モックセットアップ
        when(redisClient.getValue("password-reset:" + TOKEN, String.class)).thenReturn(Optional.of(USER_ID.toString()));

        // ユースケース実行
        assertThatCode(() -> verifyPasswordResetTokenUseCase.execute(TOKEN))
                .doesNotThrowAnyException();

        // 検証
        verify(redisClient).deleteValue(eq("password-reset:" + TOKEN));
    }

    @Test
    @DisplayName("リセットトークンが無効または期限切れの場合、UseCaseExceptionがスローされる")
    void test2() {
        // モックセットアップ
        when(redisClient.getValue("password-reset:" + TOKEN, String.class)).thenReturn(Optional.empty());

        // ユースケース実行
        assertThatThrownBy(() -> verifyPasswordResetTokenUseCase.execute(TOKEN))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("リセットリンクが無効または期限切れです。もう一度最初からお試しください。");
    }
}
