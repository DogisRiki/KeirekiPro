package com.example.keirekipro.usecase.user;

import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer.SendOutcome;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー設定の画面から確認のメールを送るユースケース
 * 設定待ちのメールアドレスがあればそちらに送り、無ければ確認前のメールアドレスに送る
 */
@Service
@RequiredArgsConstructor
public class SendAccountEmailVerificationUseCase {

    private static final String NOTHING_TO_VERIFY_MESSAGE = "確認が必要なメールアドレスはありません。";

    private static final String RATE_LIMITED_MESSAGE = "確認のメールは1分に1回まで送れます。少し待ってからもう一度お試しください。";

    private final UserRepository userRepository;

    private final EmailVerificationMailer mailer;

    /**
     * 確認のメールを送る
     *
     * @param userId ログインしている利用者のID
     */
    public void execute(UUID userId) {

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AuthenticationCredentialsNotFoundException("不正なアクセスです。"));

        SendOutcome outcome;
        if (user.getPendingEmail() != null) {
            outcome = mailer.send(user.getPendingEmail().getValue(), userId, EmailVerificationPurpose.PENDING_EMAIL);
        } else if (user.getEmail() != null && !user.isEmailVerified()) {
            outcome = mailer.send(user.getEmail().getValue(), userId, EmailVerificationPurpose.ACCOUNT_EMAIL);
        } else {
            throw new UseCaseException(NOTHING_TO_VERIFY_MESSAGE);
        }

        if (outcome == SendOutcome.RATE_LIMITED) {
            throw new UseCaseException(RATE_LIMITED_MESSAGE);
        }
    }
}
