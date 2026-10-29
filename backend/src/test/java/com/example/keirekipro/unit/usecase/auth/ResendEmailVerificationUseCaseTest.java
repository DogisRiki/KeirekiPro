package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.usecase.auth.ResendEmailVerificationUseCase;
import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationClaims;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationLinkClassifier;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationLinkClassifier.LinkState;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer.SendOutcome;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationTokenCodec;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ResendEmailVerificationUseCaseTest {

    @Mock
    private EmailVerificationTokenCodec tokenCodec;

    @Mock
    private EmailVerificationLinkClassifier linkClassifier;

    @Mock
    private EmailVerificationMailer mailer;

    @Mock
    private PendingRegistrationStore pendingRegistrationStore;

    @InjectMocks
    private ResendEmailVerificationUseCase resendEmailVerificationUseCase;

    private static final String TOKEN = "token";
    private static final UUID SUB = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";

    private EmailVerificationClaims givenClaims(EmailVerificationPurpose purpose, LinkState state) {
        EmailVerificationClaims claims = new EmailVerificationClaims(
                "jti-1", SUB, purpose, EMAIL, Instant.now().minus(Duration.ofMinutes(1)));
        when(tokenCodec.read(TOKEN)).thenReturn(Optional.of(claims));
        when(linkClassifier.classify(claims)).thenReturn(state);
        return claims;
    }

    @ParameterizedTest
    @EnumSource(EmailVerificationPurpose.class)
    @DisplayName("EXPIRED のリンクから同じ purpose で send を呼ぶ")
    void test1(EmailVerificationPurpose purpose) {
        givenClaims(purpose, LinkState.EXPIRED);
        when(mailer.send(EMAIL, SUB, purpose)).thenReturn(SendOutcome.SENT);

        resendEmailVerificationUseCase.execute(TOKEN);

        verify(mailer).send(EMAIL, SUB, purpose);
    }

    @ParameterizedTest
    @EnumSource(value = LinkState.class, names = "EXPIRED", mode = EnumSource.Mode.EXCLUDE)
    @DisplayName("EXPIRED でないリンクでは UseCaseException を投げる")
    void test2(LinkState state) {
        givenClaims(EmailVerificationPurpose.REGISTRATION, state);

        assertThatThrownBy(() -> resendEmailVerificationUseCase.execute(TOKEN))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("このリンクでは確認のメールを送り直せません。");

        verify(mailer, never()).send(any(), any(), any());
    }

    @Test
    @DisplayName("署名か aud が正しくないトークンでは UseCaseException を投げる")
    void test3() {
        when(tokenCodec.read(TOKEN)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> resendEmailVerificationUseCase.execute(TOKEN))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("このリンクでは確認のメールを送り直せません。");

        verify(mailer, never()).send(any(), any(), any());
    }

    @Test
    @DisplayName("SENT のときだけ REGISTRATION の登録の有効期限を延ばす")
    void test4() {
        givenClaims(EmailVerificationPurpose.REGISTRATION, LinkState.EXPIRED);
        when(mailer.send(EMAIL, SUB, EmailVerificationPurpose.REGISTRATION)).thenReturn(SendOutcome.SENT);

        resendEmailVerificationUseCase.execute(TOKEN);

        verify(pendingRegistrationStore).extend(SUB, Duration.ofHours(24));
    }

    @Test
    @DisplayName("REGISTRATION でないリンクでは登録の有効期限を延ばさない")
    void test5() {
        givenClaims(EmailVerificationPurpose.ACCOUNT_EMAIL, LinkState.EXPIRED);
        when(mailer.send(EMAIL, SUB, EmailVerificationPurpose.ACCOUNT_EMAIL)).thenReturn(SendOutcome.SENT);

        resendEmailVerificationUseCase.execute(TOKEN);

        verify(pendingRegistrationStore, never()).extend(any(), any());
    }

    @Test
    @DisplayName("RATE_LIMITED なら1分の文の UseCaseException を投げる")
    void test6() {
        givenClaims(EmailVerificationPurpose.REGISTRATION, LinkState.EXPIRED);
        when(mailer.send(EMAIL, SUB, EmailVerificationPurpose.REGISTRATION)).thenReturn(SendOutcome.RATE_LIMITED);

        assertThatThrownBy(() -> resendEmailVerificationUseCase.execute(TOKEN))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("確認のメールは1分に1回まで送れます。少し待ってからもう一度お試しください。");

        verify(pendingRegistrationStore, never()).extend(any(), any());
    }

    @Test
    @DisplayName("送信に失敗したら登録の有効期限を延ばさず、例外をそのまま返す")
    void test7() {
        givenClaims(EmailVerificationPurpose.REGISTRATION, LinkState.EXPIRED);
        RuntimeException failure = new IllegalStateException("mail failure");
        when(mailer.send(EMAIL, SUB, EmailVerificationPurpose.REGISTRATION)).thenThrow(failure);

        assertThatThrownBy(() -> resendEmailVerificationUseCase.execute(TOKEN)).isSameAs(failure);

        verify(pendingRegistrationStore, never()).extend(any(), any());
    }
}
