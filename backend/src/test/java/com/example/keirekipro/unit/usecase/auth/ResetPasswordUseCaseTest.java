package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.infrastructure.shared.redis.RedisClient;
import com.example.keirekipro.usecase.auth.ResetPasswordUseCase;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class ResetPasswordUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private RedisClient redisClient;

    @InjectMocks
    private ResetPasswordUseCase resetPasswordUseCase;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String USERNAME = "test-user";
    private static final String RAW_PASSWORD = "newPassword";
    private static final String HASHED_PASSWORD = "hashedNewPassword";
    private static final String TOKEN = "reset-token";
    private static final String REDIS_KEY = "password-reset:" + TOKEN;

    @Test
    @DisplayName("パスワードリセットが正常に完了する")
    void test1() {
        // データ準備
        User user = User.reconstruct(USER_ID, 1, null, "oldHash", false, null, null, USERNAME, null, null);

        // モックをセットアップ
        when(redisClient.getValue(REDIS_KEY, String.class)).thenReturn(Optional.of(USER_ID.toString()));
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(passwordEncoder.encode(RAW_PASSWORD)).thenReturn(HASHED_PASSWORD);

        // ユースケース実行
        assertThatCode(() -> resetPasswordUseCase.execute(TOKEN, RAW_PASSWORD)).doesNotThrowAnyException();

        // 検証
        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(captor.capture());
        User saved = captor.getValue();

        // パスワードが新しいハッシュに更新されていること
        assert saved.getPasswordHash().equals(HASHED_PASSWORD);

        verify(passwordEncoder).encode(RAW_PASSWORD);
        verify(redisClient).deleteValue(REDIS_KEY);
    }

    @Test
    @DisplayName("無効なトークンの場合、UseCaseExceptionがスローされる")
    void test2() {
        // モックをセットアップ
        when(redisClient.getValue(REDIS_KEY, String.class)).thenReturn(Optional.empty());

        // ユースケース実行
        assertThatThrownBy(() -> resetPasswordUseCase.execute(TOKEN, RAW_PASSWORD))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("リセットリンクが無効または期限切れです。もう一度最初からお試しください。");

        // 検証
        verify(passwordEncoder, never()).encode(RAW_PASSWORD);
        verify(userRepository, never()).save(any());
    }
}
