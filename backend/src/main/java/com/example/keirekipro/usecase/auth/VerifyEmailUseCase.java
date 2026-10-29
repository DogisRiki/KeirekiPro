package com.example.keirekipro.usecase.auth;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;

import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.shared.utils.SecurityUtil;
import com.example.keirekipro.usecase.auth.dto.VerifyEmailUseCaseDto;
import com.example.keirekipro.usecase.auth.store.EmailVerificationCurrentTokenStore;
import com.example.keirekipro.usecase.auth.store.PasswordResetTokenStore;
import com.example.keirekipro.usecase.auth.store.PendingRegistration;
import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationClaims;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationCompletion;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationLinkClassifier;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationLinkClassifier.LinkState;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationResult;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationTokenCodec;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 確認のリンクを受け付けるユースケース
 * トランザクションは持たず、DB への書き込みは EmailVerificationCompletion に任せる
 */
@Service
@RequiredArgsConstructor
public class VerifyEmailUseCase {

    /**
     * 最新の jti を消せなかったときに判定する最大の回数
     */
    private static final int MAX_ATTEMPTS = 2;

    private final EmailVerificationTokenCodec tokenCodec;

    private final EmailVerificationCurrentTokenStore currentTokenStore;

    private final PendingRegistrationStore pendingRegistrationStore;

    private final UserRepository userRepository;

    private final EmailVerificationCompletion completion;

    private final PasswordResetTokenStore passwordResetTokenStore;

    private final EmailVerificationLinkClassifier linkClassifier;

    private final SecurityUtil securityUtil;

    /**
     * 確認のリンクを受け付ける
     *
     * @param token 確認のリンクのトークン
     * @return 確認の結果
     */
    public VerifyEmailUseCaseDto execute(String token) {

        Optional<EmailVerificationClaims> read = tokenCodec.read(token);
        if (read.isEmpty()) {
            return VerifyEmailUseCaseDto.of(EmailVerificationResult.INVALID);
        }
        EmailVerificationClaims claims = read.get();

        // 同じリンクが同時に押されたときは、あとの要求が2回目の判定で ALREADY_VERIFIED になる
        for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
            LinkState state = linkClassifier.classify(claims);
            if (state != LinkState.USABLE) {
                return VerifyEmailUseCaseDto.of(toResult(state));
            }
            if (currentTokenStore.consume(claims.subjectId(), claims.jti())) {
                return complete(claims);
            }
        }

        return VerifyEmailUseCaseDto.of(EmailVerificationResult.INVALID);
    }

    /**
     * トークンの種類ごとに確認を済ませる
     * 書き込みが取り消されても、消した最新の jti は戻さない
     *
     * @param claims トークンの中身
     * @return 確認の結果
     */
    private VerifyEmailUseCaseDto complete(EmailVerificationClaims claims) {

        switch (claims.purpose()) {
            case REGISTRATION:
                return completeRegistration(claims);
            case PENDING_EMAIL:
                try {
                    completion.promotePendingEmail(claims.subjectId(), claims.email());
                } catch (DataIntegrityViolationException e) {
                    return VerifyEmailUseCaseDto.of(EmailVerificationResult.EMAIL_TAKEN);
                }
                return VerifyEmailUseCaseDto.of(EmailVerificationResult.VERIFIED);
            case PASSWORD_RESET:
                completion.verifyAccountEmail(claims.subjectId(), claims.email());
                String resetToken = securityUtil.generateRandomToken();
                // 再設定のトークンは、確認のリンクの期限より長く使えないようにする
                passwordResetTokenStore.store(
                        resetToken, claims.subjectId(), Duration.between(Instant.now(), claims.linkExpiresAt()));
                return VerifyEmailUseCaseDto.passwordResetReady(resetToken);
            case ACCOUNT_EMAIL:
            default:
                completion.verifyAccountEmail(claims.subjectId(), claims.email());
                return VerifyEmailUseCaseDto.of(EmailVerificationResult.VERIFIED);
        }
    }

    /**
     * 確認前の登録からアカウントを作る
     *
     * @param claims トークンの中身
     * @return 確認の結果
     */
    private VerifyEmailUseCaseDto completeRegistration(EmailVerificationClaims claims) {

        Optional<PendingRegistration> registration = pendingRegistrationStore.findById(claims.subjectId());
        if (registration.isEmpty()) {
            return VerifyEmailUseCaseDto.of(EmailVerificationResult.REGISTRATION_GONE);
        }

        try {
            completion.completeRegistration(registration.get());
        } catch (DataIntegrityViolationException e) {
            // 失敗したトランザクションの中では読み直せないため、トランザクションの外で読み直す
            // EMAIL_TAKEN の登録は消さず、有効期限で消えるのを待つ
            boolean alreadyVerified = userRepository.findById(claims.subjectId())
                    .filter(u -> u.isEmailVerified() && u.getEmail() != null
                            && u.getEmail().getValue().equals(claims.email()))
                    .isPresent();
            return VerifyEmailUseCaseDto.of(
                    alreadyVerified ? EmailVerificationResult.ALREADY_VERIFIED : EmailVerificationResult.EMAIL_TAKEN);
        }

        pendingRegistrationStore.delete(registration.get());
        return VerifyEmailUseCaseDto.of(EmailVerificationResult.VERIFIED);
    }

    /**
     * 使えないリンクの状態を結果にする
     *
     * @param state リンクの状態
     * @return 確認の結果
     */
    private static EmailVerificationResult toResult(LinkState state) {
        switch (state) {
            case ALREADY_VERIFIED:
                return EmailVerificationResult.ALREADY_VERIFIED;
            case EXPIRED:
                return EmailVerificationResult.EXPIRED;
            case REGISTRATION_GONE:
                return EmailVerificationResult.REGISTRATION_GONE;
            default:
                return EmailVerificationResult.INVALID;
        }
    }
}
