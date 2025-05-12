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

        // プロバイダー名を小文字で統一
        String provider = userInfo.getProviderType().toLowerCase();
        String providerUserId = userInfo.getProviderUserId();

        // 外部認証情報でユーザーを検索
        Optional<User> existingUserOpt = userRepository.findByProvider(provider, providerUserId);

        // 外部認証で見つからず、email がある場合はメールアドレスで既存ユーザーを検索
        if (existingUserOpt.isEmpty() && userInfo.getEmail() != null) {
            existingUserOpt = userRepository.findByEmail(userInfo.getEmail());
        }

        User user = existingUserOpt.map(existing -> {
            // 同一プロバイダーの場合は何もせず返す、他プロバイダーなら追加
            return existing.addAuthProvider(notification, provider, providerUserId);
        }).orElseGet(() -> {
            // 新規登録
            Map<String, AuthProvider> providers = Map.of(
                    provider, AuthProvider.create(notification, provider, providerUserId));

            User newUser = User.create(
                    notification,
                    1,
                    userInfo.getEmail() != null ? Email.create(notification, userInfo.getEmail()) : null,
                    null,
                    false,
                    providers,
                    null,
                    userInfo.getUsername());

            // メールアドレスがある場合のみイベントを発行
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
