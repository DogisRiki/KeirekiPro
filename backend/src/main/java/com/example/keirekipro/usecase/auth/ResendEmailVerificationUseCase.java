package com.example.keirekipro.usecase.auth;

import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationClaims;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationLinkClassifier;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationLinkClassifier.LinkState;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer.SendOutcome;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationTokenCodec;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 使えなくなったリンクから確認のメールを送り直すユースケース
 * 確認のリンクを受け付けるユースケースと同じ部品でリンクの状態を決め、送り直せるリンクを食い違わせない
 */
@Service
@RequiredArgsConstructor
public class ResendEmailVerificationUseCase {

    private static final String NOT_RESENDABLE_MESSAGE = "このリンクでは確認のメールを送り直せません。";

    private static final String RATE_LIMITED_MESSAGE = "確認のメールは1分に1回まで送れます。少し待ってからもう一度お試しください。";

    private final EmailVerificationTokenCodec tokenCodec;

    private final EmailVerificationLinkClassifier linkClassifier;

    private final EmailVerificationMailer mailer;

    private final PendingRegistrationStore pendingRegistrationStore;

    /**
     * 同じ宛先、同じ対象、同じ種類で確認のメールを送り直す
     *
     * @param token 使えなくなったリンクのトークン
     */
    public void execute(String token) {

        EmailVerificationClaims claims = tokenCodec.read(token)
                .filter(c -> linkClassifier.classify(c) == LinkState.EXPIRED)
                .orElseThrow(() -> new UseCaseException(NOT_RESENDABLE_MESSAGE));

        SendOutcome outcome = mailer.send(claims.email(), claims.subjectId(), claims.purpose());
        if (outcome == SendOutcome.RATE_LIMITED) {
            throw new UseCaseException(RATE_LIMITED_MESSAGE);
        }

        // 確認前の登録は、最後に送ったリンクの期限が切れるまで残す
        if (claims.purpose() == EmailVerificationPurpose.REGISTRATION) {
            pendingRegistrationStore.extend(
                    claims.subjectId(), EmailVerificationPurpose.REGISTRATION.getLinkValidity());
        }
    }
}
