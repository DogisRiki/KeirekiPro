package com.example.keirekipro.usecase.auth;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.usecase.auth.command.ResendEmailVerificationForLoginCommand;
import com.example.keirekipro.usecase.auth.store.PendingRegistration;
import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer.SendOutcome;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * ログインの画面から確認のメールを送るユースケース
 * パスワードが合ったときだけ送り、送れないときはログインと同じ文を返して、確認前の登録やアカウントの有無を漏らさない
 */
@Service
@RequiredArgsConstructor
public class ResendEmailVerificationForLoginUseCase {

    private static final String INVALID_CREDENTIALS_MESSAGE = "メールアドレスまたはパスワードが正しくありません。";

    private static final String RATE_LIMITED_MESSAGE = "確認のメールは1分に1回まで送れます。少し待ってからもう一度お試しください。";

    private static final int MAX_PENDING_REGISTRATIONS = 5;

    private final UserRepository userRepository;

    private final PasswordEncoder passwordEncoder;

    private final PendingRegistrationStore pendingRegistrationStore;

    private final EmailVerificationMailer mailer;

    /**
     * 確認のメールを送る
     *
     * @param command コマンド
     */
    public void execute(ResendEmailVerificationForLoginCommand command) {

        Optional<User> user = userRepository.findByEmail(command.getEmail());
        if (user.isPresent()) {
            sendForAccount(user.get(), command);
            return;
        }
        sendForPendingRegistration(command);
    }

    private void sendForAccount(User user, ResendEmailVerificationForLoginCommand command) {
        if (!passwordEncoder.matches(command.getPassword(), user.getPasswordHash()) || user.isEmailVerified()) {
            throw new UseCaseException(INVALID_CREDENTIALS_MESSAGE);
        }
        send(command.getEmail(), user.getId(), EmailVerificationPurpose.ACCOUNT_EMAIL);
    }

    private void sendForPendingRegistration(ResendEmailVerificationForLoginCommand command) {
        // 新しい順に照らし合わせ、最初にパスワードが合った確認前の登録に送る
        PendingRegistration registration = pendingRegistrationStore
                .findByEmail(command.getEmail(), MAX_PENDING_REGISTRATIONS).stream()
                .filter(r -> passwordEncoder.matches(command.getPassword(), r.passwordHash()))
                .findFirst()
                .orElseThrow(() -> new UseCaseException(INVALID_CREDENTIALS_MESSAGE));

        send(command.getEmail(), registration.id(), EmailVerificationPurpose.REGISTRATION);

        // 確認前の登録は、最後に送ったリンクの期限が切れるまで残す
        pendingRegistrationStore.extend(registration.id(), EmailVerificationPurpose.REGISTRATION.getLinkValidity());
    }

    private void send(String email, UUID subjectId, EmailVerificationPurpose purpose) {
        if (mailer.send(email, subjectId, purpose) == SendOutcome.RATE_LIMITED) {
            throw new UseCaseException(RATE_LIMITED_MESSAGE);
        }
    }
}
