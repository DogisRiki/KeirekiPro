package com.example.keirekipro.usecase.auth.verification;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import com.example.keirekipro.usecase.auth.notification.EmailVerificationNotification;
import com.example.keirekipro.usecase.auth.store.EmailVerificationCurrentTokenStore;
import com.example.keirekipro.usecase.auth.store.EmailVerificationSendLimiter;
import com.example.keirekipro.usecase.shared.notification.NotificationDispatcher;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * 確認のメールを送る部品
 * どの宛先に送るかと、送らなかったときに画面に何を出すかは呼ぶ側のユースケースが判断する
 */
@Component
@RequiredArgsConstructor
public class EmailVerificationMailer {

    /**
     * 送った結果
     */
    public enum SendOutcome {

        /**
         * 確認のメールを送った
         */
        SENT,

        /**
         * 同じメールアドレスへ1分以内に送っているため送らなかった
         */
        RATE_LIMITED
    }

    private final EmailVerificationSendLimiter sendLimiter;

    private final EmailVerificationTokenCodec tokenCodec;

    private final EmailVerificationCurrentTokenStore currentTokenStore;

    private final NotificationDispatcher notificationDispatcher;

    @Value("${frontend-base-url}")
    private String frontendBaseUrl;

    @Value("${spring.application.name}")
    private String applicationName;

    /**
     * 確認のメールを送る
     * 送信に失敗したときは、送ったことの記録と最新のリンクの ID を消してから例外を返す
     *
     * @param email 宛先メールアドレス
     * @param subjectId 確認前の登録かアカウントのID
     * @param purpose トークンの種類
     * @return 送った結果
     */
    public SendOutcome send(String email, UUID subjectId, EmailVerificationPurpose purpose) {

        if (!sendLimiter.tryAcquire(email)) {
            return SendOutcome.RATE_LIMITED;
        }

        Duration validity = purpose.getLinkValidity();
        String jti = UUID.randomUUID().toString();
        String token = tokenCodec.issue(new EmailVerificationClaims(
                jti, subjectId, purpose, email, Instant.now().plus(validity)));

        // 前に送ったリンクを使えなくする
        currentTokenStore.put(subjectId, jti, validity);

        // トークンを # のあとに置き、ブラウザが要求にも Referer にも載せないようにする
        String verificationLink = frontendBaseUrl + "/email/verify#" + token;

        try {
            notificationDispatcher.dispatch(new EmailVerificationNotification(
                    email,
                    verificationLink,
                    formatLifetime(validity),
                    applicationName,
                    frontendBaseUrl));
        } catch (RuntimeException e) {
            // 届かなかったメールのために、送り直しを1分待たせない
            sendLimiter.release(email);
            currentTokenStore.clear(subjectId);
            throw e;
        }

        return SendOutcome.SENT;
    }

    /**
     * リンクの期限をメールの本文に書く形にする
     *
     * @param validity リンクの期限の長さ
     * @return 「24時間」や「10分」の形の文字列
     */
    private static String formatLifetime(Duration validity) {
        if (validity.toMinutesPart() == 0) {
            return validity.toHours() + "時間";
        }
        return validity.toMinutes() + "分";
    }
}
