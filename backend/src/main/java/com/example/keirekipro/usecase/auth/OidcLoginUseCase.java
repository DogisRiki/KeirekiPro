package com.example.keirekipro.usecase.auth;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.AuthProvider;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.dto.OidcLoginUseCaseDto;
import com.example.keirekipro.usecase.auth.oidc.OidcUserInfo;
import com.example.keirekipro.usecase.auth.oidc.UnverifiedEmailAccountUseCaseException;
import com.example.keirekipro.usecase.auth.store.UserTokenVersionStore;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * OIDCログインユースケース
 */
@Service
@RequiredArgsConstructor
public class OidcLoginUseCase {

    private final UserRepository userRepository;

    private final DomainEventPublisher eventPublisher;

    private final UserTokenVersionStore userTokenVersionStore;

    /**
     * OIDCログインを実行する
     *
     * @param userInfo ユーザー情報
     * @return ログイン結果
     */
    @Transactional
    public OidcLoginUseCaseDto execute(OidcUserInfo userInfo) {

        ErrorCollector errorCollector = new ErrorCollector();
        String provider = userInfo.getProviderType().toLowerCase();
        String providerUserId = userInfo.getProviderUserId();

        // まずはプロバイダーで検索
        Optional<User> byProvider = userRepository.findByProvider(provider, providerUserId);

        // プロバイダーなし or ユーザーは存在するが、providersが部分的の場合、IDで改めて全件取得
        Optional<User> existingUser = byProvider.map(u -> userRepository.findById(u.getId())
                .orElseThrow(() -> new IllegalStateException("ユーザー情報取得に失敗しました")))
                .map(u -> applyReturnedEmail(u, userInfo.getEmail()));

        // プロバイダーでも見つからずメールがあればメールで検索
        if (existingUser.isEmpty() && userInfo.getEmail() != null) {
            existingUser = userRepository.findByEmail(userInfo.getEmail())
                    .flatMap(u -> userRepository.findById(u.getId()));

            // 確認がまだのアカウントには外部連携を結び付けない
            if (existingUser.isPresent() && !existingUser.get().isEmailVerified()) {
                throw new UnverifiedEmailAccountUseCaseException();
            }
        }

        boolean isNewUser = existingUser.isEmpty();

        User user = existingUser.map(existing -> {
            // すでに当該プロバイダーがある場合は何もせず、なければ追加
            return existing.addAuthProvider(errorCollector, provider, providerUserId);
        }).orElseGet(() -> {
            // 新規ユーザー登録
            Map<String, AuthProvider> providers = Map.of(
                    provider, AuthProvider.create(errorCollector, provider, providerUserId));
            // 外部連携が返したメールアドレスは持ち主を確かめたものなので、確認済みとして作る
            User newUser = userInfo.getEmail() != null
                    ? User.createWithVerifiedEmail(
                            errorCollector,
                            UUID.randomUUID(),
                            Email.create(errorCollector, userInfo.getEmail()),
                            null,
                            providers,
                            null,
                            userInfo.getUsername(),
                            LocalDateTime.now())
                    : User.create(
                            errorCollector,
                            null,
                            null,
                            providers,
                            null,
                            userInfo.getUsername());
            if (newUser.getEmail() != null) {
                newUser.register();
            }
            return newUser;
        });

        userRepository.save(user);

        // 新規ユーザーの場合、トークンバージョンを初期化
        if (isNewUser) {
            userTokenVersionStore.initialize(user.getId());
        }

        // ドメインイベントをパブリッシュ
        user.getDomainEvents().forEach(eventPublisher::publish);
        user.clearDomainEvents();

        return OidcLoginUseCaseDto.builder()
                .id(user.getId())
                .username(user.getUsername())
                .email(user.getEmail() != null ? user.getEmail().getValue() : null)
                .providerType(userInfo.getProviderType())
                .roles(user.getRoleNames())
                .build();
    }

    /**
     * 外部連携が持ち主を確かめたメールアドレスを、結び付いたアカウントの確認の状態に反映する
     *
     * @param user 結び付いたアカウント
     * @param returnedEmail 外部連携が返したメールアドレス(nullなら無い)
     * @return 反映後のUserエンティティ
     */
    private User applyReturnedEmail(User user, String returnedEmail) {
        if (returnedEmail == null) {
            return user;
        }

        LocalDateTime now = LocalDateTime.now();

        // 今のメールアドレスと同じなら確認済みにする
        if (user.getEmail() != null) {
            return returnedEmail.equals(user.getEmail().getValue()) ? user.verifyEmail(now) : user;
        }

        // 設定待ちのメールアドレスと同じで、ほかのアカウントが持っていなければ移す
        if (user.getPendingEmail() != null
                && returnedEmail.equals(user.getPendingEmail().getValue())
                && userRepository.findByEmail(returnedEmail).isEmpty()) {
            return user.promotePendingEmail(now);
        }

        return user;
    }
}
