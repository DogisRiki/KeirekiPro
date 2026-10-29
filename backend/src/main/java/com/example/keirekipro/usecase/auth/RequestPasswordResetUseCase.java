package com.example.keirekipro.usecase.auth;

import java.time.Duration;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.shared.utils.SecurityUtil;
import com.example.keirekipro.usecase.auth.notification.PasswordResetNotification;
import com.example.keirekipro.usecase.auth.store.PasswordResetTokenStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;
import com.example.keirekipro.usecase.shared.notification.NotificationDispatcher;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * パスワードリセット要求ユースケース
 */
@Service
@RequiredArgsConstructor
public class RequestPasswordResetUseCase {

    private final UserRepository userRepository;

    private final PasswordResetTokenStore passwordResetTokenStore;

    private final NotificationDispatcher notificationDispatcher;

    private final SecurityUtil securityUtil;

    private final EmailVerificationMailer mailer;

    @Value("${frontend-base-url}")
    private String frontendBaseUrl;

    @Value("${spring.application.name}")
    private String applicationName;

    /**
     * パスワードリセット要求ユースケースを実行する
     *
     * @param to 宛先メールアドレス
     */
    public void execute(String to) {

        Email email = Email.create(new ErrorCollector(), to);

        // 該当ユーザーを検索（存在しない場合は何もせず終了）
        userRepository.findByEmail(email.getValue())
                .ifPresent(user -> {
                    // 確認前のアカウントには、再設定のメールの代わりに確認のメールを送る。1分たっていなくても同じ応答にするため、送れたかは見ない
                    if (!user.isEmailVerified()) {
                        mailer.send(email.getValue(), user.getId(), EmailVerificationPurpose.PASSWORD_RESET);
                        return;
                    }

                    // トークンを生成
                    String token = securityUtil.generateRandomToken();

                    // トークンを保存
                    passwordResetTokenStore.store(token, user.getId(), Duration.ofMinutes(10));

                    // リセットリンクを生成
                    String resetLink = frontendBaseUrl + "/password/reset/" + token;

                    // 通知送達
                    notificationDispatcher.dispatch(new PasswordResetNotification(
                            user.getEmail().getValue(),
                            resetLink,
                            applicationName,
                            frontendBaseUrl));
                });
    }
}
