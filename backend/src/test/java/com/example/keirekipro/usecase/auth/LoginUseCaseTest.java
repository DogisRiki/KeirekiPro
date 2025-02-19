package com.example.keirekipro.usecase.auth;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.when;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.repository.user.dto.UserAuthInfoDto;
import com.example.keirekipro.infrastructure.repository.user.mapper.UserMapper;
import com.example.keirekipro.presentation.auth.dto.LoginRequest;
import com.example.keirekipro.usecase.auth.dto.LoginUseCaseDto;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;

class LoginUseCaseTest {

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private UserMapper userMapper;

    @InjectMocks
    private LoginUseCase loginUseCase;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    private static final UUID USERID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    private static final String EMAIL = "test@example.com";

    private static final String PASSWORD = "hashedPassword";

    @Test
    @DisplayName("正しいメールアドレスとパスワード")
    void test1() {
        when(userMapper.findByEmail(EMAIL))
                .thenReturn(Optional.of(new UserAuthInfoDto(USERID, EMAIL, PASSWORD)));
        when(passwordEncoder.matches(PASSWORD, PASSWORD)).thenReturn(true);

        LoginUseCaseDto dto = loginUseCase.execute(new LoginRequest(EMAIL, PASSWORD));

        // ユーザー認証情報が存在する。
        assertNotNull(dto);
        // idが正しい値である。
        assertEquals(USERID, dto.getId());
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、BadCredentialsExceptionが発生する")
    void test2() {
        when(userMapper.findByEmail(EMAIL)).thenReturn(Optional.empty());

        // BadCredentialsExceptionがスローされる。
        Exception exception = assertThrows(BadCredentialsException.class, () -> {
            loginUseCase.execute(new LoginRequest(EMAIL, PASSWORD));
        });
        // 例外メッセージが正しい値である。
        assertEquals("メールアドレスまたはパスワードが正しくありません。", exception.getMessage());
    }

    @Test
    @DisplayName("パスワードが正しくない場合、BadCredentialsExceptionが発生する")
    void test3() {
        when(userMapper.findByEmail(EMAIL))
                .thenReturn(Optional.of(new UserAuthInfoDto(USERID, EMAIL, PASSWORD)));
        when(passwordEncoder.matches(PASSWORD, PASSWORD)).thenReturn(false);

        // BadCredentialsExceptionがスローされる。
        Exception exception = assertThrows(BadCredentialsException.class, () -> {
            loginUseCase.execute(new LoginRequest(EMAIL, PASSWORD));
        });
        // 例外メッセージが正しい値である。
        assertEquals("メールアドレスまたはパスワードが正しくありません。", exception.getMessage());
    }
}
