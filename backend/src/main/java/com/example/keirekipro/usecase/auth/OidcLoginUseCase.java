package com.example.keirekipro.usecase.auth;

import java.util.Map;
import java.util.Optional;

import com.example.keirekipro.domain.model.user.AuthProvider;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.auth.dto.OidcLoginUseCaseDto;

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

    /**
     * OIDCログインを実行する
     *
     * @param userInfo ユーザー情報
     * @return ログイン結果
     */
    @Transactional
    public OidcLoginUseCaseDto execute(OidcUserInfoDto userInfo) {

        Notification notification = new Notification();
        String provider = userInfo.getProviderType().toLowerCase();
        String providerUserId = userInfo.getProviderUserId();

        // まずはプロバイダーで検索
        Optional<User> byProvider = userRepository.findByProvider(provider, providerUserId);

        // プロバイダーなし or ユーザーは存在するが providers が部分的→ID で改めて全件取得
        Optional<User> existingUser = byProvider.map(u -> userRepository.findById(u.getId())
                .orElseThrow(() -> new IllegalStateException("ユーザー情報取得に失敗しました")));

        // プロバイダーでも見つからずメールがあればメールで検索
        if (existingUser.isEmpty() && userInfo.getEmail() != null) {
            existingUser = userRepository.findByEmail(userInfo.getEmail())
                    .flatMap(u -> userRepository.findById(u.getId()));
        }

        User user = existingUser.map(existing -> {
            // すでに当該プロバイダーがある場合は何もせず、なければ追加
            return existing.addAuthProvider(notification, provider, providerUserId);
        }).orElseGet(() -> {
            // 新規ユーザー登録
            Map<String, AuthProvider> providers = Map.of(
                    provider, AuthProvider.create(notification, provider, providerUserId));
            User newUser = User.create(
                    notification,
                    userInfo.getEmail() != null ? Email.create(notification, userInfo.getEmail()) : null,
                    null,
                    false,
                    providers,
                    null,
                    userInfo.getUsername());
            if (newUser.getEmail() != null) {
                newUser.register();
            }
            return newUser;
        });

        userRepository.save(user);

        // ドメインイベントをパブリッシュ
        user.getDomainEvents().forEach(eventPublisher::publish);
        user.clearDomainEvents();

        return OidcLoginUseCaseDto.builder()
                .id(user.getId())
                .username(user.getUsername())
                .email(user.getEmail() != null ? user.getEmail().getValue() : null)
                .providerType(userInfo.getProviderType())
                .build();
    }
}
