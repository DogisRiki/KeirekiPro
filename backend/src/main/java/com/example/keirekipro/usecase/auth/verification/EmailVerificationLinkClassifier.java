package com.example.keirekipro.usecase.auth.verification;

import java.time.Instant;
import java.util.Optional;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.usecase.auth.store.EmailVerificationCurrentTokenStore;
import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;

import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * 確認のリンクの状態を決める部品
 * 書き込みは行わない。最新の jti を消すことは呼ぶ側のユースケースが行う
 */
@Component
@RequiredArgsConstructor
public class EmailVerificationLinkClassifier {

    /**
     * リンクの状態
     */
    public enum LinkState {

        /**
         * 期限内で最新のリンク
         */
        USABLE,

        /**
         * 確認がすでに済んでいる
         */
        ALREADY_VERIFIED,

        /**
         * 期限切れか、新しいメールで使えなくなったリンク
         */
        EXPIRED,

        /**
         * 確認前の登録が消えたリンク
         */
        REGISTRATION_GONE,

        /**
         * 使えないリンク
         */
        INVALID
    }

    private final UserRepository userRepository;

    private final EmailVerificationCurrentTokenStore currentTokenStore;

    private final PendingRegistrationStore pendingRegistrationStore;

    /**
     * 読んだトークンの中身からリンクの状態を決める
     *
     * @param claims トークンの中身
     * @return リンクの状態
     */
    public LinkState classify(EmailVerificationClaims claims) {

        Optional<User> user = userRepository.findById(claims.subjectId());

        if (user.filter(u -> u.isEmailVerified() && matches(u.getEmail(), claims.email())).isPresent()) {
            return LinkState.ALREADY_VERIFIED;
        }

        if (isLive(claims)) {
            return LinkState.USABLE;
        }

        if (claims.purpose() == EmailVerificationPurpose.REGISTRATION) {
            return pendingRegistrationStore.findById(claims.subjectId()).isPresent()
                    ? LinkState.EXPIRED
                    : LinkState.REGISTRATION_GONE;
        }

        // 対象のメールアドレスが今も同じときだけ、送り直せる期限切れとして扱う
        boolean sameTarget = user
                .filter(u -> matches(targetEmail(u, claims.purpose()), claims.email()))
                .isPresent();
        return sameTarget ? LinkState.EXPIRED : LinkState.INVALID;
    }

    /**
     * リンクの期限内で、jti が最新かを判定する
     *
     * @param claims トークンの中身
     * @return 期限内で最新の場合はtrue
     */
    private boolean isLive(EmailVerificationClaims claims) {
        if (!Instant.now().isBefore(claims.linkExpiresAt())) {
            return false;
        }
        return currentTokenStore.find(claims.subjectId())
                .filter(claims.jti()::equals)
                .isPresent();
    }

    /**
     * アカウントの、確認の対象のメールアドレスを返す
     *
     * @param user アカウント
     * @param purpose トークンの種類
     * @return PENDING_EMAIL なら pending_email、それ以外なら email
     */
    private static Email targetEmail(User user, EmailVerificationPurpose purpose) {
        return purpose == EmailVerificationPurpose.PENDING_EMAIL ? user.getPendingEmail() : user.getEmail();
    }

    /**
     * メールアドレスが同じかを判定する
     *
     * @param email アカウントのメールアドレス
     * @param claimedEmail トークンのメールアドレス
     * @return 同じ場合はtrue
     */
    private static boolean matches(Email email, String claimedEmail) {
        return email != null && email.getValue().equals(claimedEmail);
    }
}
