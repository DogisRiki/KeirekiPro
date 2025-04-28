package com.example.keirekipro.usecase.auth;

import java.util.Collections;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
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

    /**
     * OIDCログインを実行する
     *
     * @param userInfo ユーザー情報
     * @return ログイン結果
     */
    @Transactional
    public OidcLoginUseCaseDto execute(OidcUserInfoDto userInfo) {

        Notification notification = new Notification();

        // ユーザーを取得し、存在しなければ新規登録
        User user = userRepository.findByEmail(userInfo.getEmail())
                .orElseGet(() -> registerNewUser(userInfo, notification));

        // 外部認証連携情報を登録
        user.addAuthProvider(notification, userInfo.getProviderType(), userInfo.getProviderUserId());

        userRepository.save(user);

        return OidcLoginUseCaseDto.builder()
                .id(user.getId())
                .username(user.getUsername())
                .email(user.getEmail() != null ? user.getEmail().getValue() : null)
                .providerType(userInfo.getProviderType())
                .build();
    }

    private User registerNewUser(OidcUserInfoDto userInfo, Notification notification) {
        User user = User.create(
                notification,
                1,
                userInfo.getEmail() != null ? Email.create(
                        notification, userInfo.getEmail()) : null,
                null,
                false,
                Collections.emptyMap(),
                null,
                userInfo.getUsername());
        return user;
    }
}
