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
import com.example.keirekipro.usecase.auth.ResetPasswordUseCase;
import com.example.keirekipro.usecase.auth.store.PasswordResetTokenStore;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class ResetPasswordUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private PasswordResetTokenStore passwordResetTokenStore;

    @InjectMocks
    private ResetPasswordUseCase resetPasswordUseCase;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String USERNAME = "test-user";
    private static final String RAW_PASSWORD = "newPassword";
    private static final String HASHED_PASSWORD = "hashedNewPassword";
    private static final String TOKEN = "reset-token";

    @Test
    @DisplayName("パスワードリセットが正常に完了する")
    void test1() {
        // データ準備
        User user = User.reconstruct(USER_ID, null, "oldHash", false, null, null, USERNAME, null, null);

        // モックをセットアップ
        when(passwordResetTokenStore.findUserId(TOKEN)).thenReturn(Optional.of(USER_ID));
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
        verify(passwordResetTokenStore).remove(TOKEN);
    }

    @Test
    @DisplayName("無効なトークンの場合、UseCaseExceptionがスローされる")
    void test2() {
        // モックをセットアップ
        when(passwordResetTokenStore.findUserId(TOKEN)).thenReturn(Optional.empty());

        // ユースケース実行
        assertThatThrownBy(() -> resetPasswordUseCase.execute(TOKEN, RAW_PASSWORD))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("リセットリンクが無効または期限切れです。もう一度最初からお試しください。");

        // 検証
        verify(passwordEncoder, never()).encode(RAW_PASSWORD);
        verify(userRepository, never()).save(any());
        verify(passwordResetTokenStore, never()).remove(any());
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、AuthenticationCredentialsNotFoundExceptionがスローされる")
    void test3() {
        // モックをセットアップ：トークンは有効
        when(passwordResetTokenStore.findUserId(TOKEN)).thenReturn(Optional.of(USER_ID));
        // ユーザーが見つからない
        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());

        // ユースケース実行
        assertThatThrownBy(() -> resetPasswordUseCase.execute(TOKEN, RAW_PASSWORD))
                .isInstanceOf(AuthenticationCredentialsNotFoundException.class)
                .hasMessage("不正なアクセスです。");

        // 検証
        verify(passwordEncoder, never()).encode(RAW_PASSWORD);
        verify(userRepository, never()).save(any());
        verify(passwordResetTokenStore, never()).remove(any());
    }
}
