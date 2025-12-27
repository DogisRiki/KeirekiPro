package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.presentation.auth.dto.LoginRequest;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.LoginUseCase;
import com.example.keirekipro.usecase.auth.dto.LoginUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class LoginUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @InjectMocks
    private LoginUseCase loginUseCase;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@example.com";
    private static final String HASHED_PWD = "hashedPassword";
    private static final String RAW_PASSWORD = "rawPassword";

    @Test
    @DisplayName("正しいメールアドレスとパスワードでログインする")
    void test1() {
        // モックをセットアップ
        when(userRepository.findByEmail(EMAIL))
                .thenReturn(Optional.of(buildStoredUser(HASHED_PWD)));
        when(passwordEncoder.matches(RAW_PASSWORD, HASHED_PWD)).thenReturn(true);

        // ユースケース実行
        LoginUseCaseDto dto = loginUseCase.execute(new LoginRequest(EMAIL, RAW_PASSWORD));

        // 検証
        assertThat(dto).isNotNull();
        assertThat(dto.getId()).isEqualTo(USER_ID);
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、UseCaseExceptionが発生する")
    void test2() {
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> loginUseCase.execute(new LoginRequest(EMAIL, RAW_PASSWORD)))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("メールアドレスまたはパスワードが正しくありません。");
    }

    @Test
    @DisplayName("パスワードが正しくない場合、UseCaseExceptionが発生する")
    void test3() {
        when(userRepository.findByEmail(EMAIL))
                .thenReturn(Optional.of(buildStoredUser(HASHED_PWD)));
        when(passwordEncoder.matches(RAW_PASSWORD, HASHED_PWD)).thenReturn(false);

        assertThatThrownBy(() -> loginUseCase.execute(new LoginRequest(EMAIL, RAW_PASSWORD)))
                .isInstanceOf(
                        UseCaseException.class)
                .hasMessage("メールアドレスまたはパスワードが正しくありません。");
    }

    // テスト用ユーザー生成ヘルパー
    private static User buildStoredUser(String passwordHash) {
        ErrorCollector n = new ErrorCollector();
        return User.reconstruct(
                USER_ID,
                Email.create(n, EMAIL),
                passwordHash,
                false,
                Collections.emptyMap(),
                null,
                "tester",
                LocalDateTime.now(),
                LocalDateTime.now());
    }
}
