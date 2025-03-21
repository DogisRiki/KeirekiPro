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

import com.example.keirekipro.infrastructure.repository.user.dto.UserAuthInfoDto;
import com.example.keirekipro.infrastructure.repository.user.mapper.UserMapper;
import com.example.keirekipro.presentation.auth.dto.UserRegistrationRequest;
import com.example.keirekipro.usecase.auth.UserRegistrationUseCase;
import com.example.keirekipro.usecase.shared.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class UserRegistrationUseCaseTest {

    @Mock
    private UserMapper userMapper;

    @Mock
    private PasswordEncoder passwordEncoder;

    @InjectMocks
    private UserRegistrationUseCase userRegistrationUseCase;

    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PASSWORD = "password";
    private static final String CONFIRM_PASSWORD = "password";
    private static final String HASHED_PASSWORD = "hashedPassword";

    @Test
    @DisplayName("ユーザーを新規登録できる")
    void test1() {
        // データ準備
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, PASSWORD, CONFIRM_PASSWORD);

        // モックをセットアップ
        when(userMapper.findByEmail(request.getEmail())).thenReturn(Optional.empty());
        when(passwordEncoder.encode(eq(request.getPassword()))).thenReturn(HASHED_PASSWORD);

        // ユースケース実行
        assertThatCode(() -> {
            userRegistrationUseCase.execute(request);
        }).doesNotThrowAnyException();

        // 検証
        verify(passwordEncoder).encode(eq(request.getPassword()));
        verify(userMapper).registerUser(any(UUID.class), eq(request.getEmail()), eq(HASHED_PASSWORD),
                eq(request.getUsername()));
    }

    @Test
    @DisplayName("既にメールアドレスが登録されている場合、UseCaseExceptionがスローされる")
    void test2() {
        // データ準備
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, PASSWORD, CONFIRM_PASSWORD);
        UserAuthInfoDto dto = new UserAuthInfoDto(UUID.randomUUID(), EMAIL, PASSWORD, false);

        // モックをセットアップ
        when(userMapper.findByEmail(request.getEmail())).thenReturn(Optional.of(dto));

        // ユースケース実行
        assertThatThrownBy(() -> userRegistrationUseCase.execute(request))
                .isInstanceOf(UseCaseException.class)
                .hasMessageContaining("このメールアドレスは既に登録されています。");

        // 検証
        verify(passwordEncoder, never()).encode(any());
        verify(userMapper, never()).registerUser(any(), any(), any(), any());
    }
}
