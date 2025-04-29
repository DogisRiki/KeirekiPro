package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.usecase.auth.ResetPasswordUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class ResetPasswordUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @InjectMocks
    private ResetPasswordUseCase resetPasswordUseCase;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String USERNAME = "test-user";
    private static final String RAW_PASSWORD = "newPassword";
    private static final String HASHED_PASSWORD = "hashedNewPassword";

    @Test
    @DisplayName("パスワードリセットが正常に完了する")
    void test1() {
        // データ準備
        User user = User.reconstruct(USER_ID, 1, null, "oldHash", false, null, null, USERNAME, null, null);

        // モックをセットアップ
        when(userRepository.findById(eq(USER_ID))).thenReturn(Optional.of(user));
        when(passwordEncoder.encode(eq(RAW_PASSWORD))).thenReturn(HASHED_PASSWORD);

        // ユースケース実行
        assertThatCode(() -> resetPasswordUseCase.execute(USER_ID, RAW_PASSWORD)).doesNotThrowAnyException();

        // 検証
        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(captor.capture());
        User saved = captor.getValue();

        // パスワードが新しいハッシュに更新されていること
        assert saved.getPasswordHash().equals(HASHED_PASSWORD);

        verify(passwordEncoder).encode(eq(RAW_PASSWORD));
    }

    @Test
    @DisplayName("存在しないユーザーIDの場合、AccessDeniedExceptionがスローされる")
    void test2() {
        // モックをセットアップ
        when(userRepository.findById(eq(USER_ID))).thenReturn(Optional.empty());

        // ユースケース実行
        assertThatThrownBy(() -> resetPasswordUseCase.execute(USER_ID, RAW_PASSWORD))
                .isInstanceOf(AccessDeniedException.class)
                .hasMessage("不正なアクセスです。");

        // 検証
        verify(passwordEncoder, never()).encode(eq(RAW_PASSWORD));
        verify(userRepository, never()).save(any());
    }
}
