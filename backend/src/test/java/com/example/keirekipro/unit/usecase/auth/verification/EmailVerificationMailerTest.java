package com.example.keirekipro.unit.usecase.auth.verification;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.usecase.auth.notification.EmailVerificationNotification;
import com.example.keirekipro.usecase.auth.store.EmailVerificationCurrentTokenStore;
import com.example.keirekipro.usecase.auth.store.EmailVerificationSendLimiter;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationClaims;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer.SendOutcome;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationTokenCodec;
import com.example.keirekipro.usecase.shared.notification.NotificationDispatcher;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class EmailVerificationMailerTest {

    @Mock
    private EmailVerificationSendLimiter sendLimiter;

    @Mock
    private EmailVerificationTokenCodec tokenCodec;

    @Mock
    private EmailVerificationCurrentTokenStore currentTokenStore;

    @Mock
    private NotificationDispatcher notificationDispatcher;

    @InjectMocks
    private EmailVerificationMailer emailVerificationMailer;

    private static final String EMAIL = "test@keirekipro.click";
    private static final UUID SUBJECT_ID = UUID.randomUUID();
    private static final String FRONTEND_BASE_URL = "https://keirekipro.click";
    private static final String APPLICATION_NAME = "KeirekiPro";

    @BeforeEach
    void setUp() {
        ReflectionTestUtils.setField(emailVerificationMailer, "frontendBaseUrl", FRONTEND_BASE_URL);
        ReflectionTestUtils.setField(emailVerificationMailer, "applicationName", APPLICATION_NAME);
    }

    @Test
    @DisplayName("送ると、トークンを URL の # のあとに置いたリンクで確認のメールを送り SENT を返す")
    void test1() {
        when(sendLimiter.tryAcquire(EMAIL)).thenReturn(true);
        when(tokenCodec.issue(any())).thenReturn("token-xxx");

        SendOutcome outcome = emailVerificationMailer.send(EMAIL, SUBJECT_ID, EmailVerificationPurpose.REGISTRATION);

        assertThat(outcome).isEqualTo(SendOutcome.SENT);

        ArgumentCaptor<EmailVerificationClaims> claimsCaptor = ArgumentCaptor.forClass(EmailVerificationClaims.class);
        verify(tokenCodec).issue(claimsCaptor.capture());
        EmailVerificationClaims claims = claimsCaptor.getValue();
        assertThat(claims.subjectId()).isEqualTo(SUBJECT_ID);
        assertThat(claims.purpose()).isEqualTo(EmailVerificationPurpose.REGISTRATION);
        assertThat(claims.email()).isEqualTo(EMAIL);
        assertThat(UUID.fromString(claims.jti())).isNotNull();

        verify(currentTokenStore).put(SUBJECT_ID, claims.jti(), Duration.ofHours(24));

        ArgumentCaptor<EmailVerificationNotification> notificationCaptor = ArgumentCaptor
                .forClass(EmailVerificationNotification.class);
        verify(notificationDispatcher).dispatch(notificationCaptor.capture());
        EmailVerificationNotification notification = notificationCaptor.getValue();
        assertThat(notification.to()).isEqualTo(EMAIL);
        assertThat(notification.verificationLink()).isEqualTo(FRONTEND_BASE_URL + "/email/verify#token-xxx");
        assertThat(notification.linkLifetime()).isEqualTo("24時間");
        assertThat(notification.siteName()).isEqualTo(APPLICATION_NAME);
        assertThat(notification.siteUrl()).isEqualTo(FRONTEND_BASE_URL);

        verify(sendLimiter, never()).release(anyString());
        verify(currentTokenStore, never()).clear(any());
    }

    @Test
    @DisplayName("送るたびに最新の jti を置き換える")
    void test2() {
        when(sendLimiter.tryAcquire(EMAIL)).thenReturn(true);
        when(tokenCodec.issue(any())).thenReturn("token-1", "token-2");

        emailVerificationMailer.send(EMAIL, SUBJECT_ID, EmailVerificationPurpose.ACCOUNT_EMAIL);
        emailVerificationMailer.send(EMAIL, SUBJECT_ID, EmailVerificationPurpose.ACCOUNT_EMAIL);

        ArgumentCaptor<EmailVerificationClaims> claimsCaptor = ArgumentCaptor.forClass(EmailVerificationClaims.class);
        verify(tokenCodec, times(2)).issue(claimsCaptor.capture());
        List<EmailVerificationClaims> claims = claimsCaptor.getAllValues();
        assertThat(claims.get(0).jti()).isNotEqualTo(claims.get(1).jti());

        ArgumentCaptor<String> jtiCaptor = ArgumentCaptor.forClass(String.class);
        verify(currentTokenStore, times(2)).put(eq(SUBJECT_ID), jtiCaptor.capture(), eq(Duration.ofHours(24)));
        assertThat(jtiCaptor.getAllValues()).containsExactly(claims.get(0).jti(), claims.get(1).jti());
    }

    @Test
    @DisplayName("tryAcquire が false なら、トークンも通知も作らずに RATE_LIMITED を返す")
    void test3() {
        when(sendLimiter.tryAcquire(EMAIL)).thenReturn(false);

        SendOutcome outcome = emailVerificationMailer.send(EMAIL, SUBJECT_ID, EmailVerificationPurpose.REGISTRATION);

        assertThat(outcome).isEqualTo(SendOutcome.RATE_LIMITED);
        verifyNoInteractions(tokenCodec, currentTokenStore, notificationDispatcher);
        verify(sendLimiter, never()).release(anyString());
    }

    @Test
    @DisplayName("送信に失敗したら release と clear を呼んで例外を返す")
    void test4() {
        when(sendLimiter.tryAcquire(EMAIL)).thenReturn(true);
        when(tokenCodec.issue(any())).thenReturn("token-xxx");
        RuntimeException failure = new RuntimeException("SES failure");
        doThrow(failure).when(notificationDispatcher).dispatch(any());

        assertThatThrownBy(
                () -> emailVerificationMailer.send(EMAIL, SUBJECT_ID, EmailVerificationPurpose.REGISTRATION))
                .isSameAs(failure);

        verify(sendLimiter).release(EMAIL);
        verify(currentTokenStore).clear(SUBJECT_ID);
    }

    @Test
    @DisplayName("PASSWORD_RESET のリンクの lexp は10分後になる")
    void test5() {
        when(sendLimiter.tryAcquire(EMAIL)).thenReturn(true);
        when(tokenCodec.issue(any())).thenReturn("token-xxx");

        Instant before = Instant.now();
        emailVerificationMailer.send(EMAIL, SUBJECT_ID, EmailVerificationPurpose.PASSWORD_RESET);
        Instant after = Instant.now();

        ArgumentCaptor<EmailVerificationClaims> claimsCaptor = ArgumentCaptor.forClass(EmailVerificationClaims.class);
        verify(tokenCodec).issue(claimsCaptor.capture());
        assertThat(claimsCaptor.getValue().linkExpiresAt())
                .isBetween(before.plus(Duration.ofMinutes(10)), after.plus(Duration.ofMinutes(10)));

        verify(currentTokenStore).put(eq(SUBJECT_ID), anyString(), eq(Duration.ofMinutes(10)));

        ArgumentCaptor<EmailVerificationNotification> notificationCaptor = ArgumentCaptor
                .forClass(EmailVerificationNotification.class);
        verify(notificationDispatcher).dispatch(notificationCaptor.capture());
        assertThat(notificationCaptor.getValue().linkLifetime()).isEqualTo("10分");
    }
}
