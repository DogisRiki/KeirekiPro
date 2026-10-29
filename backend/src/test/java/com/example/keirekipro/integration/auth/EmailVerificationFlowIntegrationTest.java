package com.example.keirekipro.integration.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.verify;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import com.example.keirekipro.config.PostgresTestContainerConfig;
import com.example.keirekipro.config.RedisTestContainerConfig;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.LoginUseCase;
import com.example.keirekipro.usecase.auth.RequestPasswordResetUseCase;
import com.example.keirekipro.usecase.auth.ResendEmailVerificationForLoginUseCase;
import com.example.keirekipro.usecase.auth.ResendEmailVerificationUseCase;
import com.example.keirekipro.usecase.auth.ResetPasswordUseCase;
import com.example.keirekipro.usecase.auth.UserRegistrationUseCase;
import com.example.keirekipro.usecase.auth.VerifyEmailUseCase;
import com.example.keirekipro.usecase.auth.command.LoginCommand;
import com.example.keirekipro.usecase.auth.command.ResendEmailVerificationForLoginCommand;
import com.example.keirekipro.usecase.auth.command.UserRegistrationCommand;
import com.example.keirekipro.usecase.auth.dto.LoginUseCaseDto;
import com.example.keirekipro.usecase.auth.dto.VerifyEmailUseCaseDto;
import com.example.keirekipro.usecase.auth.notification.EmailVerificationNotification;
import com.example.keirekipro.usecase.auth.store.EmailVerificationCurrentTokenStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationClaims;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationResult;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationTokenCodec;
import com.example.keirekipro.usecase.shared.exception.EmailNotVerifiedUseCaseException;
import com.example.keirekipro.usecase.shared.notification.Notification;
import com.example.keirekipro.usecase.shared.notification.NotificationDispatcher;
import com.example.keirekipro.usecase.user.notification.UserRegisteredNotification;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.ses.SesClient;

/**
 * 登録から確認までの流れを、Testcontainers の PostgreSQL と Redis で確かめる結合テスト
 *
 * メールの送信は、通知を受け取るテスト用の部品(NotificationDispatcher のモック)に置き換え、
 * 受け取った確認のメールのリンクからトークンを読む。
 * AWS のクライアントは KeirekiProApplicationTests と同じくモックにする。
 */
@SpringBootTest
@ActiveProfiles("test")
@Import({ PostgresTestContainerConfig.class, RedisTestContainerConfig.class })
class EmailVerificationFlowIntegrationTest {

    private static final String PASSWORD = "Password123!";

    private static final String NEW_PASSWORD = "NewPassword456!";

    /**
     * 1分の送信の制限の Redis のキーの頭(RedisEmailVerificationSendLimiter と同じ)
     */
    private static final String RATE_LIMIT_PREFIX = "email-verification:rate:";

    /**
     * パスワードの再設定のトークンの Redis のキーの頭(RedisPasswordResetTokenStore と同じ)
     */
    private static final String PASSWORD_RESET_PREFIX = "password-reset:";

    @MockitoBean
    private SecretsManagerClient secretsManagerClient;

    @MockitoBean
    private S3Client s3Client;

    @MockitoBean
    private S3Presigner s3Presigner;

    @MockitoBean
    private SesClient sesClient;

    @MockitoBean
    private NotificationDispatcher notificationDispatcher;

    @Autowired
    private UserRegistrationUseCase userRegistrationUseCase;

    @Autowired
    private VerifyEmailUseCase verifyEmailUseCase;

    @Autowired
    private ResendEmailVerificationUseCase resendEmailVerificationUseCase;

    @Autowired
    private ResendEmailVerificationForLoginUseCase resendEmailVerificationForLoginUseCase;

    @Autowired
    private RequestPasswordResetUseCase requestPasswordResetUseCase;

    @Autowired
    private ResetPasswordUseCase resetPasswordUseCase;

    @Autowired
    private LoginUseCase loginUseCase;

    @Autowired
    private EmailVerificationTokenCodec tokenCodec;

    @Autowired
    private EmailVerificationCurrentTokenStore currentTokenStore;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    @BeforeEach
    void setUp() {
        Mockito.clearInvocations(notificationDispatcher);
    }

    @Test
    void 登録_確認のリンク_アカウントの作成_登録完了のお知らせの順に通り_確認前の登録の段階ではusersに行が無い() {
        String email = uniqueEmail();

        userRegistrationUseCase.execute(new UserRegistrationCommand(email, "flow-user", PASSWORD));

        // 確認前の登録の段階では、users に行が無い
        assertThat(countUsers(email)).isZero();
        List<Notification> beforeVerify = dispatchedNotifications();
        assertThat(beforeVerify).hasSize(1);
        String token = tokenOf(beforeVerify.get(0), email);

        VerifyEmailUseCaseDto result = verifyEmailUseCase.execute(token);

        assertThat(result.getResult()).isEqualTo(EmailVerificationResult.VERIFIED);
        // 確認を済ませると、確認済みのアカウントができる
        assertThat(countUsers(email)).isOne();
        assertThat(jdbcTemplate.queryForObject(
                "SELECT email_verified_at FROM users WHERE email = ?", LocalDateTime.class, email)).isNotNull();
        // 確認のメールのあとに、登録完了のお知らせのメールを送る
        List<Notification> all = dispatchedNotifications();
        assertThat(all).hasSize(2);
        assertThat(all.get(0)).isInstanceOf(EmailVerificationNotification.class);
        assertThat(all.get(1)).isInstanceOfSatisfying(UserRegisteredNotification.class,
                n -> assertThat(n.to()).isEqualTo(email));
    }

    @Test
    void 同じメールアドレスの2つの確認前の登録を同時に確認すると_1つだけがアカウントになり_もう1つがEMAIL_TAKENになる() throws Exception {
        String email = uniqueEmail();

        userRegistrationUseCase.execute(new UserRegistrationCommand(email, "first-user", PASSWORD));
        // 1分の制限を過ぎたものとして、2つ目の登録にも確認のメールを送る
        redisTemplate.delete(RATE_LIMIT_PREFIX + email);
        userRegistrationUseCase.execute(new UserRegistrationCommand(email, "second-user", PASSWORD));

        List<Notification> notifications = dispatchedNotifications();
        assertThat(notifications).hasSize(2);
        String firstToken = tokenOf(notifications.get(0), email);
        String secondToken = tokenOf(notifications.get(1), email);
        assertThat(firstToken).isNotEqualTo(secondToken);

        List<EmailVerificationResult> results = verifyAtTheSameTime(firstToken, secondToken);

        assertThat(results).containsExactlyInAnyOrder(
                EmailVerificationResult.VERIFIED, EmailVerificationResult.EMAIL_TAKEN);
        assertThat(countUsers(email)).isOne();
    }

    @Test
    void 新しい確認のメールを送ったあとに前のリンクがEXPIREDになり_送り直しで同じpurposeのリンクが届く() {
        String email = uniqueEmail();

        userRegistrationUseCase.execute(new UserRegistrationCommand(email, "resend-user", PASSWORD));
        String oldToken = tokenOf(dispatchedNotifications().get(0), email);

        // 1分の制限を過ぎたものとして、ログインの画面から新しい確認のメールを送る
        redisTemplate.delete(RATE_LIMIT_PREFIX + email);
        resendEmailVerificationForLoginUseCase.execute(new ResendEmailVerificationForLoginCommand(email, PASSWORD));

        // 前のリンクは使えない
        assertThat(verifyEmailUseCase.execute(oldToken).getResult()).isEqualTo(EmailVerificationResult.EXPIRED);

        // 使えなくなったリンクから送り直す
        redisTemplate.delete(RATE_LIMIT_PREFIX + email);
        resendEmailVerificationUseCase.execute(oldToken);

        List<Notification> notifications = dispatchedNotifications();
        assertThat(notifications).hasSize(3);
        EmailVerificationClaims oldClaims = claimsOf(oldToken);
        EmailVerificationClaims resentClaims = claimsOf(tokenOf(notifications.get(2), email));
        assertThat(resentClaims.purpose()).isEqualTo(EmailVerificationPurpose.REGISTRATION);
        assertThat(resentClaims.subjectId()).isEqualTo(oldClaims.subjectId());
        assertThat(resentClaims.jti()).isNotEqualTo(oldClaims.jti());
        // 送り直したリンクで確認を済ませられる
        assertThat(verifyEmailUseCase.execute(tokenOf(notifications.get(2), email)).getResult())
                .isEqualTo(EmailVerificationResult.VERIFIED);
    }

    @Test
    void 前からあるアカウントのパスワードの再設定の要求から_確認_パスワードの再設定_ログインまでが通り_再設定のトークンの有効期限がリンクの期限までの残りである() {
        String email = uniqueEmail();
        ErrorCollector errorCollector = new ErrorCollector();
        // 前からあるアカウント(メールアドレスの確認がまだ)
        User existing = User.create(errorCollector, Email.create(errorCollector, email),
                passwordEncoder.encode(PASSWORD), Collections.emptyMap(), null, "existing-user");
        userRepository.save(existing);

        // 確認がまだのあいだは、ログインできない
        assertThatThrownBy(() -> {
            LoginUseCaseDto ignored = loginUseCase.execute(new LoginCommand(email, PASSWORD));
            assertThat(ignored).isNotNull();
        }).isInstanceOf(EmailNotVerifiedUseCaseException.class);

        requestPasswordResetUseCase.execute(email);

        List<Notification> notifications = dispatchedNotifications();
        assertThat(notifications).hasSize(1);
        String token = tokenOf(notifications.get(0), email);
        EmailVerificationClaims claims = claimsOf(token);
        assertThat(claims.purpose()).isEqualTo(EmailVerificationPurpose.PASSWORD_RESET);
        assertThat(claims.subjectId()).isEqualTo(existing.getId());

        // 送った直後のリンクは期限までの残りが10分とほぼ同じで、再設定のトークンの期限を固定の10分にした誤りと区別できない。
        // そこで、送ってから7分たったものとして、同じ宛先と種類で期限までの残りを3分にしたリンクを出し直し、最新のリンクにする
        EmailVerificationClaims shortened = new EmailVerificationClaims(UUID.randomUUID().toString(),
                claims.subjectId(), claims.purpose(), claims.email(), Instant.now().plus(Duration.ofMinutes(3)));
        currentTokenStore.put(shortened.subjectId(), shortened.jti(), Duration.ofMinutes(3));

        VerifyEmailUseCaseDto result = verifyEmailUseCase.execute(tokenCodec.issue(shortened));

        assertThat(result.getResult()).isEqualTo(EmailVerificationResult.PASSWORD_RESET_READY);
        assertThat(result.getPasswordResetToken()).isNotBlank();
        // 再設定のトークンは、確認のリンクの期限までの残りだけ使える
        Long ttlSeconds = redisTemplate.getExpire(PASSWORD_RESET_PREFIX + result.getPasswordResetToken(),
                TimeUnit.SECONDS);
        long remainingSeconds = Duration.between(Instant.now(), shortened.linkExpiresAt()).getSeconds();
        assertThat(ttlSeconds).isNotNull();
        assertThat(ttlSeconds).isBetween(remainingSeconds - 5, remainingSeconds + 1);
        assertThat(ttlSeconds).isLessThan(Duration.ofMinutes(5).getSeconds());
        assertThat(userRepository.findById(existing.getId()).orElseThrow().isEmailVerified()).isTrue();

        resetPasswordUseCase.execute(result.getPasswordResetToken(), NEW_PASSWORD);

        // 確認を済ませたあとは、今と同じにログインできる
        LoginUseCaseDto login = loginUseCase.execute(new LoginCommand(email, NEW_PASSWORD));
        assertThat(login.getId()).isEqualTo(existing.getId());
        assertThat(login.getEmail()).isEqualTo(email);
    }

    /**
     * 2つの確認のリンクを、2つのスレッドから同時に受け付ける
     */
    private List<EmailVerificationResult> verifyAtTheSameTime(String firstToken, String secondToken)
            throws Exception {
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            Future<EmailVerificationResult> first = executor.submit(verifyAfter(start, firstToken));
            Future<EmailVerificationResult> second = executor.submit(verifyAfter(start, secondToken));
            start.countDown();
            return List.of(first.get(30, TimeUnit.SECONDS), second.get(30, TimeUnit.SECONDS));
        } finally {
            executor.shutdownNow();
        }
    }

    private Callable<EmailVerificationResult> verifyAfter(CountDownLatch start, String token) {
        return () -> {
            start.await();
            return verifyEmailUseCase.execute(token).getResult();
        };
    }

    /**
     * テスト用の部品が受け取った通知を、受け取った順に返す
     */
    private List<Notification> dispatchedNotifications() {
        ArgumentCaptor<Notification> captor = ArgumentCaptor.forClass(Notification.class);
        verify(notificationDispatcher, atLeastOnce()).dispatch(captor.capture());
        return captor.getAllValues();
    }

    /**
     * 確認のメールのリンクからトークンを読む
     */
    private static String tokenOf(Notification notification, String email) {
        assertThat(notification).isInstanceOf(EmailVerificationNotification.class);
        EmailVerificationNotification mail = (EmailVerificationNotification) notification;
        assertThat(mail.to()).isEqualTo(email);
        assertThat(mail.verificationLink()).contains("/email/verify#");
        return mail.verificationLink().substring(mail.verificationLink().indexOf('#') + 1);
    }

    private EmailVerificationClaims claimsOf(String token) {
        return tokenCodec.read(token).orElseThrow();
    }

    private Integer countUsers(String email) {
        return jdbcTemplate.queryForObject("SELECT COUNT(*) FROM users WHERE email = ?", Integer.class, email);
    }

    private static String uniqueEmail() {
        return "flow-" + UUID.randomUUID() + "@example.com";
    }
}
