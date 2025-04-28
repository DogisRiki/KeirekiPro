package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.presentation.auth.dto.UserRegistrationRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.auth.UserRegistrationUseCase;
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
class UserRegistrationUseCaseTest {

    @Mock
    private UserRepository userRepository;

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
        when(userRepository.findByEmail(eq(EMAIL))).thenReturn(Optional.empty());
        when(passwordEncoder.encode(eq(PASSWORD))).thenReturn(HASHED_PASSWORD);

        // ユースケース実行
        assertThatCode(() -> userRegistrationUseCase.execute(request)).doesNotThrowAnyException();

        // 検証
        verify(passwordEncoder).encode(eq(PASSWORD));
        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(captor.capture());
        User saved = captor.getValue();
        assert saved.getEmail().getValue().equals(EMAIL);
        assert saved.getPasswordHash().equals(HASHED_PASSWORD);
        assert saved.getUsername().equals(USERNAME);
    }

    @Test
    @DisplayName("既にメールアドレスが登録されている場合、UseCaseExceptionがスローされる")
    void test2() {
        // データ準備
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, PASSWORD, CONFIRM_PASSWORD);
        Notification notification = new Notification();
        User existing = User.create(notification, 1, Email.create(notification, EMAIL), HASHED_PASSWORD,
                false, null, null, USERNAME);

        // モックをセットアップ
        when(userRepository.findByEmail(eq(EMAIL))).thenReturn(Optional.of(existing));

        // ユースケース実行
        assertThatThrownBy(() -> userRegistrationUseCase.execute(request))
                .isInstanceOf(UseCaseException.class)
                .matches(e -> {
                    UseCaseException ex = (UseCaseException) e;
                    return ex.getErrors().containsKey("email")
                            && ex.getErrors().get("email").contains("このメールアドレスは既に登録されています。");
                });

        // 検証
        verify(passwordEncoder, never()).encode(any());
        verify(userRepository, never()).save(any());
    }
}
