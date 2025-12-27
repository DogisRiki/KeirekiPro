package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.presentation.user.dto.SetEmailAndPasswordRequest;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.user.SetEmailAndPasswordUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class SetEmailAndPasswordUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private DomainEventPublisher eventPublisher;

    @InjectMocks
    private SetEmailAndPasswordUseCase setEmailAndPasswordUseCase;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";
    private static final String RAW_PASSWORD = "Password123";
    private static final String ENCODED_PASSWORD = "encoded-password";
    private static final String USERNAME = "test-user";

    @Test
    @DisplayName("パスワードのみを設定する")
    void test1() {
        // モックをセットアップ
        User user = User.reconstruct(USER_ID, Email.create(new ErrorCollector(), EMAIL), null, false, Map.of(), null,
                USERNAME, null, null);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(passwordEncoder.encode(RAW_PASSWORD)).thenReturn(ENCODED_PASSWORD);

        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(null, RAW_PASSWORD, RAW_PASSWORD);
        setEmailAndPasswordUseCase.execute(USER_ID, request);

        // 検証
        verify(userRepository).save(any(User.class));
    }

    @Test
    @DisplayName("メールアドレスとパスワードを設定する")
    void test2() {
        // モックをセットアップ
        User user = User.reconstruct(USER_ID, null, null, false, Map.of(), null, USERNAME, null, null);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(passwordEncoder.encode(RAW_PASSWORD)).thenReturn(ENCODED_PASSWORD);

        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(EMAIL, RAW_PASSWORD, RAW_PASSWORD);
        setEmailAndPasswordUseCase.execute(USER_ID, request);

        // 検証
        verify(userRepository).save(any(User.class));
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、AuthenticationCredentialsNotFoundExceptionがスローされる")
    void test3() {
        // モックをセットアップ
        when(userRepository.findById(eq(USER_ID))).thenReturn(Optional.empty());

        assertThatThrownBy(() -> setEmailAndPasswordUseCase.execute(USER_ID, any()))
                .isInstanceOf(AuthenticationCredentialsNotFoundException.class)
                .hasMessage("不正なアクセスです。");

        // 検証
        verify(userRepository, never()).save(any());
    }
}
