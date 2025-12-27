package com.example.keirekipro.usecase.user;

import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.shared.ErrorCollector;

import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 外部認証連携解除ユースケース
 */
@Service
@RequiredArgsConstructor
public class RemoveAuthProviderUseCase {

    private final UserRepository userRepository;

    /**
     * 外部認証連携解除ユースケースを実行する
     *
     * @param userId   対象ユーザーID
     * @param provider 解除対象のプロバイダ
     */
    @Transactional
    public void execute(UUID userId, String provider) {

        // 対象ユーザーを取得
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AuthenticationCredentialsNotFoundException("不正なアクセスです。"));

        // プロバイダ解除
        ErrorCollector errorCollector = new ErrorCollector();
        user = user.removeAuthProvider(errorCollector, provider);

        // 保存
        userRepository.save(user);
    }
}
