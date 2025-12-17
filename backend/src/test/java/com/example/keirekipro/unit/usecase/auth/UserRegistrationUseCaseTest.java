package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.service.user.UserEmailDuplicationCheckService;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.presentation.auth.dto.UserRegistrationRequest;
import com.example.keirekipro.usecase.auth.UserRegistrationUseCase;

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

    @Mock
    private UserEmailDuplicationCheckService userEmailDuplicationCheckService;

    @InjectMocks
    private UserRegistrationUseCase userRegistrationUseCase;

    @Mock
    private DomainEventPublisher eventPublisher;

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
        doNothing().when(userEmailDuplicationCheckService).execute(any());
        when(passwordEncoder.encode(PASSWORD)).thenReturn(HASHED_PASSWORD);

        // ユースケース実行
        assertThatCode(() -> userRegistrationUseCase.execute(request)).doesNotThrowAnyException();

        // 検証
        verify(userEmailDuplicationCheckService).execute(any());
        verify(passwordEncoder).encode(PASSWORD);
        verify(eventPublisher, atLeastOnce()).publish(any());
        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(captor.capture());
        User saved = captor.getValue();
        assert saved.getEmail().getValue().equals(EMAIL);
        assert saved.getPasswordHash().equals(HASHED_PASSWORD);
        assert saved.getUsername().equals(USERNAME);
    }

    @Test
    @DisplayName("既にメールアドレスが登録されている場合、DomainExceptionがスローされ、後続の処理が行われない")
    void test2() {
        // データ準備
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, PASSWORD, CONFIRM_PASSWORD);

        // モックをセットアップ
        doThrow(new DomainException("このメールアドレスは登録できません。"))
                .when(userEmailDuplicationCheckService).execute(any());

        // ユースケース実行
        assertThatThrownBy(() -> userRegistrationUseCase.execute(request))
                .isInstanceOf(DomainException.class)
                .hasMessage("このメールアドレスは登録できません。");

        // 検証
        verify(userEmailDuplicationCheckService).execute(any());
        verify(passwordEncoder, never()).encode(any());
        verify(userRepository, never()).save(any());
        verify(eventPublisher, never()).publish(any());
    }
}
