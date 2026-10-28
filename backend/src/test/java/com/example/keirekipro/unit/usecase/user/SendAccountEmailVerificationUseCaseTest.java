package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.EnumSet;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.RoleName;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer.SendOutcome;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;
import com.example.keirekipro.usecase.user.SendAccountEmailVerificationUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;

@ExtendWith(MockitoExtension.class)
class SendAccountEmailVerificationUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private EmailVerificationMailer mailer;

    @InjectMocks
    private SendAccountEmailVerificationUseCase sendAccountEmailVerificationUseCase;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@keirekipro.click";
    private static final String PENDING_EMAIL = "new@keirekipro.click";
    private static final String NOTHING_TO_VERIFY_MESSAGE = "確認が必要なメールアドレスはありません。";
    private static final LocalDateTime VERIFIED_AT = LocalDateTime.of(2024, 1, 1, 0, 0);

    @Test
    @DisplayName("pending_email があれば PENDING_EMAIL で送る")
    void test1() {
        // email も確認前だが、設定待ちのメールアドレスを先に送る
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(buildStoredUser(EMAIL, null, PENDING_EMAIL)));
        when(mailer.send(PENDING_EMAIL, USER_ID, EmailVerificationPurpose.PENDING_EMAIL)).thenReturn(SendOutcome.SENT);

        sendAccountEmailVerificationUseCase.execute(USER_ID);

        verify(mailer).send(PENDING_EMAIL, USER_ID, EmailVerificationPurpose.PENDING_EMAIL);
        verify(mailer, never()).send(EMAIL, USER_ID, EmailVerificationPurpose.ACCOUNT_EMAIL);
    }

    @Test
    @DisplayName("pending_email が無く email が確認前なら ACCOUNT_EMAIL で送る")
    void test2() {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(buildStoredUser(EMAIL, null, null)));
        when(mailer.send(EMAIL, USER_ID, EmailVerificationPurpose.ACCOUNT_EMAIL)).thenReturn(SendOutcome.SENT);

        sendAccountEmailVerificationUseCase.execute(USER_ID);

        verify(mailer).send(EMAIL, USER_ID, EmailVerificationPurpose.ACCOUNT_EMAIL);
    }

    @Test
    @DisplayName("確認が必要なメールアドレスが無ければ UseCaseException を投げる")
    void test3() {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(buildStoredUser(EMAIL, VERIFIED_AT, null)));

        assertThatThrownBy(() -> sendAccountEmailVerificationUseCase.execute(USER_ID))
                .isExactlyInstanceOf(UseCaseException.class)
                .hasMessage(NOTHING_TO_VERIFY_MESSAGE);

        verify(mailer, never()).send(any(), any(), any());
    }

    @Test
    @DisplayName("メールアドレスも設定待ちのメールアドレスも無ければ UseCaseException を投げる")
    void test4() {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(buildStoredUser(null, null, null)));

        assertThatThrownBy(() -> sendAccountEmailVerificationUseCase.execute(USER_ID))
                .isExactlyInstanceOf(UseCaseException.class)
                .hasMessage(NOTHING_TO_VERIFY_MESSAGE);

        verify(mailer, never()).send(any(), any(), any());
    }

    @Test
    @DisplayName("RATE_LIMITED なら1分の文の UseCaseException を投げる")
    void test5() {
        when(userRepository.findById(USER_ID))
                .thenReturn(Optional.of(buildStoredUser(EMAIL, VERIFIED_AT, PENDING_EMAIL)));
        when(mailer.send(PENDING_EMAIL, USER_ID, EmailVerificationPurpose.PENDING_EMAIL))
                .thenReturn(SendOutcome.RATE_LIMITED);

        assertThatThrownBy(() -> sendAccountEmailVerificationUseCase.execute(USER_ID))
                .isExactlyInstanceOf(UseCaseException.class)
                .hasMessage("確認のメールは1分に1回まで送れます。少し待ってからもう一度お試しください。");
    }

    @Test
    @DisplayName("アカウントが無ければ AuthenticationCredentialsNotFoundException を投げる")
    void test6() {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> sendAccountEmailVerificationUseCase.execute(USER_ID))
                .isInstanceOf(AuthenticationCredentialsNotFoundException.class);

        verify(mailer, never()).send(any(), any(), any());
    }

    private static User buildStoredUser(String email, LocalDateTime emailVerifiedAt, String pendingEmail) {
        ErrorCollector n = new ErrorCollector();
        return User.reconstruct(
                USER_ID,
                email == null ? null : Email.create(n, email),
                "hashedPassword",
                false,
                Collections.emptyMap(),
                EnumSet.of(RoleName.USER),
                null,
                "tester",
                LocalDateTime.now(),
                LocalDateTime.now(),
                emailVerifiedAt,
                pendingEmail == null ? null : Email.create(n, pendingEmail));
    }
}
