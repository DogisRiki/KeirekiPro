package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

import java.time.Duration;

import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.service.user.UserEmailDuplicationCheckService;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.usecase.auth.UserRegistrationUseCase;
import com.example.keirekipro.usecase.auth.command.UserRegistrationCommand;
import com.example.keirekipro.usecase.auth.store.PendingRegistration;
import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer.SendOutcome;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;

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

    @Mock
    private PendingRegistrationStore pendingRegistrationStore;

    @Mock
    private EmailVerificationMailer mailer;

    @InjectMocks
    private UserRegistrationUseCase userRegistrationUseCase;

    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PASSWORD = "password";
    private static final String HASHED_PASSWORD = "hashedPassword";

    private final UserRegistrationCommand command = new UserRegistrationCommand(EMAIL, USERNAME, PASSWORD);

    private PendingRegistration captureSavedRegistration() {
        ArgumentCaptor<PendingRegistration> captor = ArgumentCaptor.forClass(PendingRegistration.class);
        verify(pendingRegistrationStore).save(captor.capture(), eq(Duration.ofHours(24)));
        return captor.getValue();
    }

    @Test
    @DisplayName("登録を受け付けると確認前の登録を24時間で置き、REGISTRATION の確認のメールを送り、アカウントを保存しない")
    void test1() {
        when(passwordEncoder.encode(PASSWORD)).thenReturn(HASHED_PASSWORD);
        when(mailer.send(eq(EMAIL), any(), eq(EmailVerificationPurpose.REGISTRATION))).thenReturn(SendOutcome.SENT);

        userRegistrationUseCase.execute(command);

        PendingRegistration saved = captureSavedRegistration();
        assertThat(saved.id()).isNotNull();
        assertThat(saved.email()).isEqualTo(EMAIL);
        assertThat(saved.passwordHash()).isEqualTo(HASHED_PASSWORD);
        assertThat(saved.username()).isEqualTo(USERNAME);
        assertThat(saved.createdAt()).isNotNull();
        verify(mailer).send(EMAIL, saved.id(), EmailVerificationPurpose.REGISTRATION);
        verifyNoInteractions(userRepository);
    }

    @Test
    @DisplayName("同じメールアドレスの確認前の登録があっても受け付ける")
    void test2() {
        when(passwordEncoder.encode(PASSWORD)).thenReturn(HASHED_PASSWORD);
        when(mailer.send(eq(EMAIL), any(), eq(EmailVerificationPurpose.REGISTRATION))).thenReturn(SendOutcome.SENT);

        userRegistrationUseCase.execute(command);
        userRegistrationUseCase.execute(command);

        // 確認前の登録はメールアドレスで探さず、受け付けるたびに別のIDで置く
        ArgumentCaptor<PendingRegistration> captor = ArgumentCaptor.forClass(PendingRegistration.class);
        verify(pendingRegistrationStore, times(2)).save(captor.capture(), eq(Duration.ofHours(24)));
        assertThat(captor.getAllValues().get(0).id()).isNotEqualTo(captor.getAllValues().get(1).id());
        verifyNoMoreInteractions(pendingRegistrationStore);
    }

    @Test
    @DisplayName("users にあるメールアドレスでは今と同じ DomainException を投げる")
    void test3() {
        doThrow(new DomainException("このメールアドレスは登録できません。"))
                .when(userEmailDuplicationCheckService).execute(any());

        assertThatThrownBy(() -> userRegistrationUseCase.execute(command))
                .isInstanceOf(DomainException.class)
                .hasMessage("このメールアドレスは登録できません。");

        verifyNoInteractions(pendingRegistrationStore, mailer, userRepository);
    }

    @Test
    @DisplayName("RATE_LIMITED でも例外を投げない")
    void test4() {
        when(passwordEncoder.encode(PASSWORD)).thenReturn(HASHED_PASSWORD);
        when(mailer.send(eq(EMAIL), any(), eq(EmailVerificationPurpose.REGISTRATION)))
                .thenReturn(SendOutcome.RATE_LIMITED);

        assertThatCode(() -> userRegistrationUseCase.execute(command)).doesNotThrowAnyException();

        captureSavedRegistration();
        verify(pendingRegistrationStore, never()).delete(any());
    }

    @Test
    @DisplayName("send が例外を投げたら置いた登録を消す")
    void test5() {
        when(passwordEncoder.encode(PASSWORD)).thenReturn(HASHED_PASSWORD);
        RuntimeException failure = new IllegalStateException("mail failure");
        when(mailer.send(eq(EMAIL), any(), eq(EmailVerificationPurpose.REGISTRATION))).thenThrow(failure);

        assertThatThrownBy(() -> userRegistrationUseCase.execute(command)).isSameAs(failure);

        PendingRegistration saved = captureSavedRegistration();
        verify(pendingRegistrationStore).delete(saved);
    }
}
