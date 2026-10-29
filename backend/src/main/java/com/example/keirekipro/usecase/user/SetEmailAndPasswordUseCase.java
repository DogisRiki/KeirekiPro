package com.example.keirekipro.usecase.user;

import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.service.user.UserEmailDuplicationCheckService;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.store.EmailVerificationCurrentTokenStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;
import com.example.keirekipro.usecase.user.command.SetEmailAndPasswordCommand;

import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * メールアドレス+パスワード設定ユースケース
 * メールアドレスは設定待ちにして確認のメールを送り、確認が済むまでアカウントのメールアドレスにしない
 */
@Service
@RequiredArgsConstructor
public class SetEmailAndPasswordUseCase {

    private static final String WRONG_CURRENT_PASSWORD_MESSAGE = "今のパスワードが正しくありません。";

    private final UserRepository userRepository;

    private final PasswordEncoder passwordEncoder;

    private final UserEmailDuplicationCheckService userEmailDuplicationCheckService;

    private final EmailVerificationCurrentTokenStore currentTokenStore;

    private final EmailVerificationMailer mailer;

    /**
     * メールアドレス+パスワードの設定ユースケースを実行する
     *
     * @param command コマンド
     */
    @Transactional
    public void execute(SetEmailAndPasswordCommand command) {
        UUID userId = command.getUserId();

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AuthenticationCredentialsNotFoundException("不正なアクセスです。"));

        ErrorCollector errorCollector = new ErrorCollector();

        Email email = null;
        if (command.getEmail() != null) {
            email = Email.create(errorCollector, command.getEmail());
            userEmailDuplicationCheckService.execute(email);
        }

        // パスワードを持つアカウントでは、今のパスワードが合うときだけ受け付ける
        if (user.getPasswordHash() != null && (command.getCurrentPassword() == null
                || !passwordEncoder.matches(command.getCurrentPassword(), user.getPasswordHash()))) {
            throw new UseCaseException(WRONG_CURRENT_PASSWORD_MESSAGE);
        }

        if (email != null) {
            user = user.setPendingEmail(errorCollector, email);
        }

        if (command.getPassword() != null) {
            String passwordHash = passwordEncoder.encode(command.getPassword());
            user = user.resetPassword(passwordHash);
        }

        userRepository.save(user);

        if (email != null) {
            // 前のリンクを使えなくしてから送る。1分たっていなくても同じ応答にするため、送れたかは見ない
            currentTokenStore.clear(userId);
            mailer.send(email.getValue(), userId, EmailVerificationPurpose.PENDING_EMAIL);
        }
    }
}
