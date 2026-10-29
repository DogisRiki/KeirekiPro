package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.EnumSet;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.RoleName;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.shared.utils.SecurityUtil;
import com.example.keirekipro.usecase.auth.VerifyEmailUseCase;
import com.example.keirekipro.usecase.auth.dto.VerifyEmailUseCaseDto;
import com.example.keirekipro.usecase.auth.store.EmailVerificationCurrentTokenStore;
import com.example.keirekipro.usecase.auth.store.PasswordResetTokenStore;
import com.example.keirekipro.usecase.auth.store.PendingRegistration;
import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationClaims;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationCompletion;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationLinkClassifier;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationLinkClassifier.LinkState;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationResult;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationTokenCodec;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;

@ExtendWith(MockitoExtension.class)
class VerifyEmailUseCaseTest {

    @Mock
    private EmailVerificationTokenCodec tokenCodec;

    @Mock
    private EmailVerificationCurrentTokenStore currentTokenStore;

    @Mock
    private PendingRegistrationStore pendingRegistrationStore;

    @Mock
    private UserRepository userRepository;

    @Mock
    private EmailVerificationCompletion completion;

    @Mock
    private PasswordResetTokenStore passwordResetTokenStore;

    @Mock
    private EmailVerificationLinkClassifier linkClassifier;

    @Mock
    private SecurityUtil securityUtil;

    @InjectMocks
    private VerifyEmailUseCase verifyEmailUseCase;

    private static final String TOKEN = "token";
    private static final String JTI = "jti-1";
    private static final UUID SUB = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";
    private static final String OTHER_EMAIL = "other@keirekipro.click";
    private static final String RESET_TOKEN = "reset-token";

    private EmailVerificationClaims givenClaims(EmailVerificationPurpose purpose, Instant linkExpiresAt) {
        EmailVerificationClaims claims = new EmailVerificationClaims(JTI, SUB, purpose, EMAIL, linkExpiresAt);
        when(tokenCodec.read(TOKEN)).thenReturn(Optional.of(claims));
        return claims;
    }

    private EmailVerificationClaims givenUsableClaims(EmailVerificationPurpose purpose) {
        EmailVerificationClaims claims = givenClaims(purpose, Instant.now().plus(Duration.ofHours(1)));
        when(linkClassifier.classify(claims)).thenReturn(LinkState.USABLE);
        when(currentTokenStore.consume(SUB, JTI)).thenReturn(true);
        return claims;
    }

    private static PendingRegistration registration() {
        return new PendingRegistration(SUB, EMAIL, "hashedPassword", "test-user", Instant.now());
    }

    private static User user(String email, LocalDateTime emailVerifiedAt) {
        return User.reconstruct(
                SUB,
                Email.create(new ErrorCollector(), email),
                "hashedPassword",
                false,
                null,
                EnumSet.of(RoleName.USER),
                null,
                "test-user",
                LocalDateTime.of(2024, 1, 1, 0, 0),
                null,
                emailVerifiedAt,
                null);
    }

    @Test
    @DisplayName("REGISTRATION のリンクで登録を完了し、登録と ID の集合の中の ID を消して VERIFIED を返す")
    void test1() {
        givenUsableClaims(EmailVerificationPurpose.REGISTRATION);
        PendingRegistration registration = registration();
        when(pendingRegistrationStore.findById(SUB)).thenReturn(Optional.of(registration));

        VerifyEmailUseCaseDto result = verifyEmailUseCase.execute(TOKEN);

        assertThat(result.getResult()).isEqualTo(EmailVerificationResult.VERIFIED);
        assertThat(result.getPasswordResetToken()).isNull();
        verify(completion).completeRegistration(registration);
        verify(pendingRegistrationStore).delete(registration);
    }

    @Test
    @DisplayName("一意の制約で失敗し、sub のアカウントが email を持たなければ EMAIL_TAKEN を返す")
    void test2() {
        givenUsableClaims(EmailVerificationPurpose.REGISTRATION);
        PendingRegistration registration = registration();
        when(pendingRegistrationStore.findById(SUB)).thenReturn(Optional.of(registration));
        doThrow(new DataIntegrityViolationException("duplicate email"))
                .when(completion).completeRegistration(registration);
        when(userRepository.findById(SUB)).thenReturn(Optional.empty());

        VerifyEmailUseCaseDto result = verifyEmailUseCase.execute(TOKEN);

        assertThat(result.getResult()).isEqualTo(EmailVerificationResult.EMAIL_TAKEN);
        // 登録は有効期限で消えるまで残す
        verify(pendingRegistrationStore, never()).delete(any());
    }

    @Test
    @DisplayName("一意の制約で失敗し、読み直した sub のアカウントが email を確認済みで持てば ALREADY_VERIFIED を返す")
    void test3() {
        givenUsableClaims(EmailVerificationPurpose.REGISTRATION);
        PendingRegistration registration = registration();
        when(pendingRegistrationStore.findById(SUB)).thenReturn(Optional.of(registration));
        doThrow(new DataIntegrityViolationException("duplicate email"))
                .when(completion).completeRegistration(registration);
        when(userRepository.findById(SUB)).thenReturn(Optional.of(user(EMAIL, LocalDateTime.now())));

        VerifyEmailUseCaseDto result = verifyEmailUseCase.execute(TOKEN);

        assertThat(result.getResult()).isEqualTo(EmailVerificationResult.ALREADY_VERIFIED);
    }

    @Test
    @DisplayName("一意の制約で失敗し、読み直した sub のアカウントが別のメールアドレスを持てば EMAIL_TAKEN を返す")
    void test4() {
        givenUsableClaims(EmailVerificationPurpose.REGISTRATION);
        PendingRegistration registration = registration();
        when(pendingRegistrationStore.findById(SUB)).thenReturn(Optional.of(registration));
        doThrow(new DataIntegrityViolationException("duplicate email"))
                .when(completion).completeRegistration(registration);
        when(userRepository.findById(SUB)).thenReturn(Optional.of(user(OTHER_EMAIL, LocalDateTime.now())));

        VerifyEmailUseCaseDto result = verifyEmailUseCase.execute(TOKEN);

        assertThat(result.getResult()).isEqualTo(EmailVerificationResult.EMAIL_TAKEN);
    }

    @Test
    @DisplayName("PENDING_EMAIL のリンクが一意の制約で失敗したら EMAIL_TAKEN を返す")
    void test5() {
        givenUsableClaims(EmailVerificationPurpose.PENDING_EMAIL);
        doThrow(new DataIntegrityViolationException("duplicate email"))
                .when(completion).promotePendingEmail(SUB, EMAIL);

        VerifyEmailUseCaseDto result = verifyEmailUseCase.execute(TOKEN);

        assertThat(result.getResult()).isEqualTo(EmailVerificationResult.EMAIL_TAKEN);
    }

    @Test
    @DisplayName("PENDING_EMAIL のリンクで設定待ちのメールアドレスを移して VERIFIED を返す")
    void test6() {
        givenUsableClaims(EmailVerificationPurpose.PENDING_EMAIL);

        VerifyEmailUseCaseDto result = verifyEmailUseCase.execute(TOKEN);

        assertThat(result.getResult()).isEqualTo(EmailVerificationResult.VERIFIED);
        verify(completion).promotePendingEmail(SUB, EMAIL);
    }

    @Test
    @DisplayName("ACCOUNT_EMAIL のリンクでアカウントのメールアドレスを確認済みにして VERIFIED を返す")
    void test7() {
        givenUsableClaims(EmailVerificationPurpose.ACCOUNT_EMAIL);

        VerifyEmailUseCaseDto result = verifyEmailUseCase.execute(TOKEN);

        assertThat(result.getResult()).isEqualTo(EmailVerificationResult.VERIFIED);
        verify(completion).verifyAccountEmail(SUB, EMAIL);
        verify(passwordResetTokenStore, never()).store(anyString(), any(), any());
    }

    @Test
    @DisplayName("PASSWORD_RESET のリンクで確認を済ませ、PASSWORD_RESET_READY と再設定のトークンを返す")
    void test8() {
        givenUsableClaims(EmailVerificationPurpose.PASSWORD_RESET);
        when(securityUtil.generateRandomToken()).thenReturn(RESET_TOKEN);

        VerifyEmailUseCaseDto result = verifyEmailUseCase.execute(TOKEN);

        assertThat(result.getResult()).isEqualTo(EmailVerificationResult.PASSWORD_RESET_READY);
        assertThat(result.getPasswordResetToken()).isEqualTo(RESET_TOKEN);
        verify(completion).verifyAccountEmail(SUB, EMAIL);
        verify(passwordResetTokenStore).store(eq(RESET_TOKEN), eq(SUB), any(Duration.class));
    }

    @Test
    @DisplayName("再設定のトークンの有効期限は lexp までの残りである")
    void test9() {
        EmailVerificationClaims claims = givenClaims(
                EmailVerificationPurpose.PASSWORD_RESET, Instant.now().plus(Duration.ofMinutes(7)));
        when(linkClassifier.classify(claims)).thenReturn(LinkState.USABLE);
        when(currentTokenStore.consume(SUB, JTI)).thenReturn(true);
        when(securityUtil.generateRandomToken()).thenReturn(RESET_TOKEN);

        verifyEmailUseCase.execute(TOKEN);

        ArgumentCaptor<Duration> ttlCaptor = ArgumentCaptor.forClass(Duration.class);
        verify(passwordResetTokenStore).store(eq(RESET_TOKEN), eq(SUB), ttlCaptor.capture());
        assertThat(ttlCaptor.getValue())
                .isLessThanOrEqualTo(Duration.ofMinutes(7))
                .isGreaterThan(Duration.ofMinutes(6));
    }

    @Test
    @DisplayName("最新の jti を消せなければ1回だけやり直し、2回目は ALREADY_VERIFIED か INVALID を返す")
    void test10() {
        EmailVerificationClaims claims = givenClaims(
                EmailVerificationPurpose.ACCOUNT_EMAIL, Instant.now().plus(Duration.ofHours(1)));
        when(linkClassifier.classify(claims)).thenReturn(LinkState.USABLE, LinkState.ALREADY_VERIFIED);
        when(currentTokenStore.consume(SUB, JTI)).thenReturn(false);

        VerifyEmailUseCaseDto result = verifyEmailUseCase.execute(TOKEN);

        assertThat(result.getResult()).isEqualTo(EmailVerificationResult.ALREADY_VERIFIED);
        verify(linkClassifier, times(2)).classify(claims);
        verify(completion, never()).verifyAccountEmail(any(), any());
    }

    @Test
    @DisplayName("2回目も最新の jti を消せなければ INVALID を返し、書き込まない")
    void test11() {
        EmailVerificationClaims claims = givenClaims(
                EmailVerificationPurpose.ACCOUNT_EMAIL, Instant.now().plus(Duration.ofHours(1)));
        when(linkClassifier.classify(claims)).thenReturn(LinkState.USABLE);
        when(currentTokenStore.consume(SUB, JTI)).thenReturn(false);

        VerifyEmailUseCaseDto result = verifyEmailUseCase.execute(TOKEN);

        assertThat(result.getResult()).isEqualTo(EmailVerificationResult.INVALID);
        verify(currentTokenStore, times(2)).consume(SUB, JTI);
        verify(completion, never()).verifyAccountEmail(any(), any());
    }

    @Test
    @DisplayName("署名か aud が正しくないトークンは INVALID を返す")
    void test12() {
        when(tokenCodec.read(TOKEN)).thenReturn(Optional.empty());

        VerifyEmailUseCaseDto result = verifyEmailUseCase.execute(TOKEN);

        assertThat(result.getResult()).isEqualTo(EmailVerificationResult.INVALID);
        verify(linkClassifier, never()).classify(any());
    }

    @Test
    @DisplayName("使えないリンクはリンクの状態と同じ結果を返し、最新の jti を消さない")
    void test13() {
        EmailVerificationClaims claims = givenClaims(
                EmailVerificationPurpose.REGISTRATION, Instant.now().minus(Duration.ofMinutes(1)));
        when(linkClassifier.classify(claims)).thenReturn(
                LinkState.ALREADY_VERIFIED, LinkState.EXPIRED, LinkState.REGISTRATION_GONE, LinkState.INVALID);

        assertThat(verifyEmailUseCase.execute(TOKEN).getResult()).isEqualTo(EmailVerificationResult.ALREADY_VERIFIED);
        assertThat(verifyEmailUseCase.execute(TOKEN).getResult()).isEqualTo(EmailVerificationResult.EXPIRED);
        assertThat(verifyEmailUseCase.execute(TOKEN).getResult())
                .isEqualTo(EmailVerificationResult.REGISTRATION_GONE);
        assertThat(verifyEmailUseCase.execute(TOKEN).getResult()).isEqualTo(EmailVerificationResult.INVALID);
        verify(currentTokenStore, never()).consume(any(), any());
    }

    @Test
    @DisplayName("一意の制約のほかの例外はそのまま返す")
    void test14() {
        givenUsableClaims(EmailVerificationPurpose.ACCOUNT_EMAIL);
        RuntimeException failure = new IllegalStateException("mail failure");
        doThrow(failure).when(completion).verifyAccountEmail(SUB, EMAIL);

        assertThatThrownBy(() -> verifyEmailUseCase.execute(TOKEN)).isSameAs(failure);
    }
}
