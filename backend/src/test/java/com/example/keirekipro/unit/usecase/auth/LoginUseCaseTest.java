package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.repository.user.dto.UserAuthInfoDto;
import com.example.keirekipro.infrastructure.repository.user.mapper.UserMapper;
import com.example.keirekipro.presentation.auth.dto.LoginRequest;
import com.example.keirekipro.usecase.auth.LoginUseCase;
import com.example.keirekipro.usecase.auth.dto.LoginUseCaseDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class LoginUseCaseTest {

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private UserMapper userMapper;

    @InjectMocks
    private LoginUseCase loginUseCase;

    private static final UUID USERID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    private static final String EMAIL = "test@example.com";

    private static final String PASSWORD = "hashedPassword";

    @Test
    @DisplayName("正しいメールアドレスとパスワードでログインする")
    void test1() {
        // モックをセットアップ
        when(userMapper.findByEmail(EMAIL))
                .thenReturn(Optional.of(new UserAuthInfoDto(USERID, EMAIL, PASSWORD)));
        when(passwordEncoder.matches(PASSWORD, PASSWORD)).thenReturn(true);

        LoginUseCaseDto dto = loginUseCase.execute(new LoginRequest(EMAIL, PASSWORD));

        // ユーザー認証情報が存在する
        assertThat(dto).isNotNull();
        // idが正しい
        assertThat(dto.getId()).isEqualTo(USERID);
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、BadCredentialsExceptionが発生する")
    void test2() {
        // モックをセットアップ
        when(userMapper.findByEmail(EMAIL)).thenReturn(Optional.empty());

        // BadCredentialsExceptionがスローされる
        assertThatThrownBy(() -> {
            loginUseCase.execute(new LoginRequest(EMAIL, PASSWORD));
        })
                .isInstanceOf(BadCredentialsException.class)
                .hasMessage("メールアドレスまたはパスワードが正しくありません。");
    }

    @Test
    @DisplayName("パスワードが正しくない場合、BadCredentialsExceptionが発生する")
    void test3() {
        // モックをセットアップ
        when(userMapper.findByEmail(EMAIL))
                .thenReturn(Optional.of(new UserAuthInfoDto(USERID, EMAIL, PASSWORD)));
        when(passwordEncoder.matches(PASSWORD, PASSWORD)).thenReturn(false);

        // BadCredentialsExceptionがスローされる
        assertThatThrownBy(() -> {
            loginUseCase.execute(new LoginRequest(EMAIL, PASSWORD));
        })
                .isInstanceOf(BadCredentialsException.class)
                .hasMessage("メールアドレスまたはパスワードが正しくありません。");
    }
}
