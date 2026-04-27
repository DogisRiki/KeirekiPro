package com.example.keirekipro.usecase.user;

import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.usecase.auth.session.AuthSessionInvalidator;

import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー退会ユースケース
 */
@Service
@RequiredArgsConstructor
public class DeleteUserUseCase {

    private final UserRepository userRepository;

    private final DomainEventPublisher eventPublisher;

    private final AuthSessionInvalidator authSessionInvalidator;

    /**
     * ユーザー退会ユースケースを実行する
     *
     * @param userId ユーザーID
     */
    @Transactional
    public void execute(UUID userId) {

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AuthenticationCredentialsNotFoundException("不正なアクセスです。"));

        // 退会イベントを発行する
        user.delete();

        // ユーザー削除
        userRepository.delete(userId);

        // 退会後、認証セッションを無効化
        authSessionInvalidator.invalidate(userId);

        // 退会イベントをパブリッシュ
        user.getDomainEvents().forEach(eventPublisher::publish);
        user.clearDomainEvents();
    }
}
