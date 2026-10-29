package com.example.keirekipro.unit.usecase.auth.verification;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
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
import com.example.keirekipro.usecase.auth.store.EmailVerificationCurrentTokenStore;
import com.example.keirekipro.usecase.auth.store.PendingRegistration;
import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationClaims;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationLinkClassifier;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationLinkClassifier.LinkState;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class EmailVerificationLinkClassifierTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private EmailVerificationCurrentTokenStore currentTokenStore;

    @Mock
    private PendingRegistrationStore pendingRegistrationStore;

    @InjectMocks
    private EmailVerificationLinkClassifier classifier;

    private static final UUID SUB = UUID.randomUUID();
    private static final String JTI = "jti-1";
    private static final String EMAIL = "test@keirekipro.click";
    private static final String OTHER_EMAIL = "other@keirekipro.click";
    private static final LocalDateTime VERIFIED_AT = LocalDateTime.of(2026, 1, 1, 0, 0);

    private static EmailVerificationClaims claims(EmailVerificationPurpose purpose, Instant linkExpiresAt) {
        return new EmailVerificationClaims(JTI, SUB, purpose, EMAIL, linkExpiresAt);
    }

    private static Instant future() {
        return Instant.now().plus(Duration.ofHours(1));
    }

    private static Instant past() {
        return Instant.now().minus(Duration.ofMinutes(1));
    }

    private static User user(String email, LocalDateTime emailVerifiedAt, String pendingEmail) {
        ErrorCollector errorCollector = new ErrorCollector();
        return User.reconstruct(
                SUB,
                email == null ? null : Email.create(errorCollector, email),
                "hashedPassword",
                false,
                null,
                EnumSet.of(RoleName.USER),
                null,
                "test-user",
                LocalDateTime.of(2024, 1, 1, 0, 0),
                null,
                emailVerifiedAt,
                pendingEmail == null ? null : Email.create(errorCollector, pendingEmail));
    }

    @Test
    @DisplayName("lexp 前で jti が最新のリンクは USABLE")
    void test1() {
        when(userRepository.findById(SUB)).thenReturn(Optional.empty());
        when(currentTokenStore.find(SUB)).thenReturn(Optional.of(JTI));

        LinkState state = classifier.classify(claims(EmailVerificationPurpose.REGISTRATION, future()));

        assertThat(state).isEqualTo(LinkState.USABLE);
    }

    @Test
    @DisplayName("sub のアカウントが email を確認済みで持てば ALREADY_VERIFIED")
    void test2() {
        when(userRepository.findById(SUB)).thenReturn(Optional.of(user(EMAIL, VERIFIED_AT, null)));

        LinkState state = classifier.classify(claims(EmailVerificationPurpose.ACCOUNT_EMAIL, future()));

        assertThat(state).isEqualTo(LinkState.ALREADY_VERIFIED);
        verify(currentTokenStore, never()).find(any());
    }

    @Test
    @DisplayName("sub のアカウントが email を持っていても確認がまだなら ALREADY_VERIFIED にしない")
    void test3() {
        when(userRepository.findById(SUB)).thenReturn(Optional.of(user(EMAIL, null, null)));
        when(currentTokenStore.find(SUB)).thenReturn(Optional.of(JTI));

        LinkState state = classifier.classify(claims(EmailVerificationPurpose.ACCOUNT_EMAIL, future()));

        assertThat(state).isEqualTo(LinkState.USABLE);
    }

    @Test
    @DisplayName("sub のアカウントが別のメールアドレスを確認済みで持つときは ALREADY_VERIFIED にしない")
    void test4() {
        when(userRepository.findById(SUB)).thenReturn(Optional.of(user(OTHER_EMAIL, VERIFIED_AT, EMAIL)));
        when(currentTokenStore.find(SUB)).thenReturn(Optional.of(JTI));

        LinkState state = classifier.classify(claims(EmailVerificationPurpose.PENDING_EMAIL, future()));

        assertThat(state).isEqualTo(LinkState.USABLE);
    }

    @Test
    @DisplayName("lexp を過ぎたリンクは EXPIRED")
    void test5() {
        when(userRepository.findById(SUB)).thenReturn(Optional.of(user(EMAIL, null, null)));

        LinkState state = classifier.classify(claims(EmailVerificationPurpose.ACCOUNT_EMAIL, past()));

        assertThat(state).isEqualTo(LinkState.EXPIRED);
    }

    @Test
    @DisplayName("jti が最新でないリンクは EXPIRED")
    void test6() {
        when(userRepository.findById(SUB)).thenReturn(Optional.of(user(EMAIL, null, null)));
        when(currentTokenStore.find(SUB)).thenReturn(Optional.of("jti-2"));

        LinkState state = classifier.classify(claims(EmailVerificationPurpose.PASSWORD_RESET, future()));

        assertThat(state).isEqualTo(LinkState.EXPIRED);
    }

    @Test
    @DisplayName("最新の jti が無いリンクは EXPIRED")
    void test7() {
        when(userRepository.findById(SUB)).thenReturn(Optional.of(user(EMAIL, null, null)));
        when(currentTokenStore.find(SUB)).thenReturn(Optional.empty());

        LinkState state = classifier.classify(claims(EmailVerificationPurpose.ACCOUNT_EMAIL, future()));

        assertThat(state).isEqualTo(LinkState.EXPIRED);
    }

    @Test
    @DisplayName("確認前の登録が残る REGISTRATION の使えないリンクは EXPIRED")
    void test8() {
        when(userRepository.findById(SUB)).thenReturn(Optional.empty());
        when(pendingRegistrationStore.findById(SUB)).thenReturn(Optional.of(
                new PendingRegistration(SUB, EMAIL, "hashedPassword", "test-user", Instant.now())));

        LinkState state = classifier.classify(claims(EmailVerificationPurpose.REGISTRATION, past()));

        assertThat(state).isEqualTo(LinkState.EXPIRED);
    }

    @Test
    @DisplayName("確認前の登録が無い REGISTRATION のリンクは REGISTRATION_GONE")
    void test9() {
        when(userRepository.findById(SUB)).thenReturn(Optional.empty());
        when(pendingRegistrationStore.findById(SUB)).thenReturn(Optional.empty());

        LinkState state = classifier.classify(claims(EmailVerificationPurpose.REGISTRATION, past()));

        assertThat(state).isEqualTo(LinkState.REGISTRATION_GONE);
    }

    @Test
    @DisplayName("PENDING_EMAIL の使えないリンクは pending_email が email と同じなら EXPIRED")
    void test10() {
        when(userRepository.findById(SUB)).thenReturn(Optional.of(user(OTHER_EMAIL, VERIFIED_AT, EMAIL)));

        LinkState state = classifier.classify(claims(EmailVerificationPurpose.PENDING_EMAIL, past()));

        assertThat(state).isEqualTo(LinkState.EXPIRED);
    }

    @Test
    @DisplayName("PENDING_EMAIL の使えないリンクは pending_email が email と違えば INVALID")
    void test11() {
        when(userRepository.findById(SUB)).thenReturn(Optional.of(user(EMAIL, null, OTHER_EMAIL)));

        LinkState state = classifier.classify(claims(EmailVerificationPurpose.PENDING_EMAIL, past()));

        assertThat(state).isEqualTo(LinkState.INVALID);
    }

    @Test
    @DisplayName("ACCOUNT_EMAIL の使えないリンクはアカウントの email が email と違えば INVALID")
    void test12() {
        when(userRepository.findById(SUB)).thenReturn(Optional.of(user(OTHER_EMAIL, null, null)));

        LinkState state = classifier.classify(claims(EmailVerificationPurpose.ACCOUNT_EMAIL, past()));

        assertThat(state).isEqualTo(LinkState.INVALID);
    }

    @Test
    @DisplayName("REGISTRATION 以外の使えないリンクは sub のアカウントが無ければ INVALID")
    void test13() {
        when(userRepository.findById(SUB)).thenReturn(Optional.empty());

        LinkState state = classifier.classify(claims(EmailVerificationPurpose.PASSWORD_RESET, past()));

        assertThat(state).isEqualTo(LinkState.INVALID);
    }
}
