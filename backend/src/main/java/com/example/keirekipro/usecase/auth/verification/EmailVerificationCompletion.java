package com.example.keirekipro.usecase.auth.verification;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.store.PendingRegistration;
import com.example.keirekipro.usecase.auth.store.UserTokenVersionStore;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 確認を済ませたときに DB へ書き込む部品
 * 一時データの片付けは呼ぶ側のユースケースが、この部品のトランザクションが確定してから行う
 */
@Component
@RequiredArgsConstructor
public class EmailVerificationCompletion {

    private static final String INVALID_LINK_MESSAGE = "確認のリンクが無効です。";

    private final UserRepository userRepository;

    private final UserTokenVersionStore userTokenVersionStore;

    private final DomainEventPublisher eventPublisher;

    /**
     * 確認前の登録から、確認済みのアカウントを作る
     * 一意の制約に当たったときの DataIntegrityViolationException はそのまま返す
     *
     * @param registration 確認前の登録
     */
    @Transactional
    public void completeRegistration(PendingRegistration registration) {

        ErrorCollector errorCollector = new ErrorCollector();

        User user = User.createWithVerifiedEmail(
                errorCollector,
                registration.id(),
                Email.create(errorCollector, registration.email()),
                registration.passwordHash(),
                Collections.emptyMap(),
                null,
                registration.username(),
                LocalDateTime.now());

        // 新規登録イベントを発行する
        user.register();

        userRepository.save(user);

        userTokenVersionStore.initialize(user.getId());

        // 登録完了のメールの送信が失敗したら、このトランザクションごと取り消す
        user.getDomainEvents().forEach(eventPublisher::publish);
        user.clearDomainEvents();
    }

    /**
     * アカウントの今のメールアドレスを確認済みにする
     *
     * @param userId アカウントのID
     * @param email トークンのメールアドレス
     */
    @Transactional
    public void verifyAccountEmail(UUID userId, String email) {

        User user = findUser(userId);

        if (!matches(user.getEmail(), email)) {
            throw new UseCaseException(INVALID_LINK_MESSAGE);
        }

        userRepository.save(user.verifyEmail(LocalDateTime.now()));
    }

    /**
     * アカウントの設定待ちのメールアドレスを、確認済みのメールアドレスにする
     *
     * @param userId アカウントのID
     * @param email トークンのメールアドレス
     */
    @Transactional
    public void promotePendingEmail(UUID userId, String email) {

        User user = findUser(userId);

        if (!matches(user.getPendingEmail(), email)) {
            throw new UseCaseException(INVALID_LINK_MESSAGE);
        }

        userRepository.save(user.promotePendingEmail(LocalDateTime.now()));
    }

    /**
     * アカウントを取得する
     *
     * @param userId アカウントのID
     * @return アカウント
     */
    private User findUser(UUID userId) {
        return userRepository.findById(userId)
                .orElseThrow(() -> new UseCaseException(INVALID_LINK_MESSAGE));
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
