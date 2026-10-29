package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.EnumSet;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.RoleName;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.ResendEmailVerificationForLoginUseCase;
import com.example.keirekipro.usecase.auth.command.ResendEmailVerificationForLoginCommand;
import com.example.keirekipro.usecase.auth.store.PendingRegistration;
import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer.SendOutcome;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class ResendEmailVerificationForLoginUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private PendingRegistrationStore pendingRegistrationStore;

    @Mock
    private EmailVerificationMailer mailer;

    @InjectMocks
    private ResendEmailVerificationForLoginUseCase resendEmailVerificationForLoginUseCase;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@keirekipro.click";
    private static final String HASHED_PWD = "hashedPassword";
    private static final String RAW_PASSWORD = "rawPassword";
    private static final String INVALID_CREDENTIALS_MESSAGE = "メールアドレスまたはパスワードが正しくありません。";

    private final ResendEmailVerificationForLoginCommand command = new ResendEmailVerificationForLoginCommand(
            EMAIL, RAW_PASSWORD);

    @Test
    @DisplayName("確認前の登録のパスワードが合えば REGISTRATION の確認のメールを送り、SENT のときだけ有効期限を延ばす")
    void test1() {
        PendingRegistration newer = buildRegistration("newerHash");
        PendingRegistration older = buildRegistration("olderHash");
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());
        when(pendingRegistrationStore.findByEmail(EMAIL, 5)).thenReturn(List.of(newer, older));
        when(passwordEncoder.matches(RAW_PASSWORD, "newerHash")).thenReturn(false);
        when(passwordEncoder.matches(RAW_PASSWORD, "olderHash")).thenReturn(true);
        when(mailer.send(EMAIL, older.id(), EmailVerificationPurpose.REGISTRATION)).thenReturn(SendOutcome.SENT);

        resendEmailVerificationForLoginUseCase.execute(command);

        verify(mailer).send(EMAIL, older.id(), EmailVerificationPurpose.REGISTRATION);
        verify(pendingRegistrationStore).extend(older.id(), Duration.ofHours(24));
    }

    @Test
    @DisplayName("確認前のアカウントのパスワードが合えば ACCOUNT_EMAIL の確認のメールを送る")
    void test2() {
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(buildStoredUser(null)));
        when(passwordEncoder.matches(RAW_PASSWORD, HASHED_PWD)).thenReturn(true);
        when(mailer.send(EMAIL, USER_ID, EmailVerificationPurpose.ACCOUNT_EMAIL)).thenReturn(SendOutcome.SENT);

        resendEmailVerificationForLoginUseCase.execute(command);

        verify(mailer).send(EMAIL, USER_ID, EmailVerificationPurpose.ACCOUNT_EMAIL);
        verify(pendingRegistrationStore, never()).extend(any(), any());
    }

    @Test
    @DisplayName("パスワードが違えばログインと同じ UseCaseException を投げる")
    void test3() {
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(buildStoredUser(null)));
        when(passwordEncoder.matches(RAW_PASSWORD, HASHED_PWD)).thenReturn(false);

        assertThatThrownBy(() -> resendEmailVerificationForLoginUseCase.execute(command))
                .isExactlyInstanceOf(UseCaseException.class)
                .hasMessage(INVALID_CREDENTIALS_MESSAGE);

        verify(mailer, never()).send(any(), any(), any());
    }

    @Test
    @DisplayName("確認前の登録のパスワードが違えばログインと同じ UseCaseException を投げる")
    void test4() {
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());
        when(pendingRegistrationStore.findByEmail(EMAIL, 5)).thenReturn(List.of(buildRegistration("otherHash")));
        when(passwordEncoder.matches(RAW_PASSWORD, "otherHash")).thenReturn(false);

        assertThatThrownBy(() -> resendEmailVerificationForLoginUseCase.execute(command))
                .isExactlyInstanceOf(UseCaseException.class)
                .hasMessage(INVALID_CREDENTIALS_MESSAGE);

        verify(mailer, never()).send(any(), any(), any());
        verify(pendingRegistrationStore, never()).extend(any(), any());
    }

    @Test
    @DisplayName("確認済みのアカウントには送らず、ログインと同じ UseCaseException を投げる")
    void test5() {
        when(userRepository.findByEmail(EMAIL))
                .thenReturn(Optional.of(buildStoredUser(LocalDateTime.of(2024, 1, 1, 0, 0))));
        when(passwordEncoder.matches(RAW_PASSWORD, HASHED_PWD)).thenReturn(true);

        assertThatThrownBy(() -> resendEmailVerificationForLoginUseCase.execute(command))
                .isExactlyInstanceOf(UseCaseException.class)
                .hasMessage(INVALID_CREDENTIALS_MESSAGE);

        verify(mailer, never()).send(any(), any(), any());
    }

    @Test
    @DisplayName("RATE_LIMITED なら1分の文の UseCaseException を投げる")
    void test6() {
        PendingRegistration registration = buildRegistration("matchedHash");
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());
        when(pendingRegistrationStore.findByEmail(EMAIL, 5)).thenReturn(List.of(registration));
        when(passwordEncoder.matches(RAW_PASSWORD, "matchedHash")).thenReturn(true);
        when(mailer.send(EMAIL, registration.id(), EmailVerificationPurpose.REGISTRATION))
                .thenReturn(SendOutcome.RATE_LIMITED);

        assertThatThrownBy(() -> resendEmailVerificationForLoginUseCase.execute(command))
                .isExactlyInstanceOf(UseCaseException.class)
                .hasMessage("確認のメールは1分に1回まで送れます。少し待ってからもう一度お試しください。");

        verify(pendingRegistrationStore, never()).extend(any(), any());
    }

    @Test
    @DisplayName("送信に失敗したら登録の有効期限を延ばさず、例外をそのまま返す")
    void test7() {
        PendingRegistration registration = buildRegistration("matchedHash");
        IllegalStateException failure = new IllegalStateException("mail failure");
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());
        when(pendingRegistrationStore.findByEmail(EMAIL, 5)).thenReturn(List.of(registration));
        when(passwordEncoder.matches(RAW_PASSWORD, "matchedHash")).thenReturn(true);
        when(mailer.send(EMAIL, registration.id(), EmailVerificationPurpose.REGISTRATION)).thenThrow(failure);

        assertThatThrownBy(() -> resendEmailVerificationForLoginUseCase.execute(command)).isSameAs(failure);

        verify(pendingRegistrationStore, never()).extend(any(), any());
    }

    private static PendingRegistration buildRegistration(String passwordHash) {
        return new PendingRegistration(UUID.randomUUID(), EMAIL, passwordHash, "tester", Instant.now());
    }

    private static User buildStoredUser(LocalDateTime emailVerifiedAt) {
        ErrorCollector n = new ErrorCollector();
        return User.reconstruct(
                USER_ID,
                Email.create(n, EMAIL),
                HASHED_PWD,
                false,
                Collections.emptyMap(),
                EnumSet.of(RoleName.USER),
                null,
                "tester",
                LocalDateTime.now(),
                LocalDateTime.now(),
                emailVerifiedAt,
                null);
    }
}
