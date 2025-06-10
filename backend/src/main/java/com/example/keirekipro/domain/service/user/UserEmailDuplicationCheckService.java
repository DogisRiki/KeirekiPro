package com.example.keirekipro.domain.service.user;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.shared.exception.DomainException;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * ユーザーのメールアドレス重複チェックドメインサービス
 */
@Service
@RequiredArgsConstructor
public class UserEmailDuplicationCheckService {

    private final UserRepository userRepository;

    /**
     * メールアドレスの重複をチェックする
     *
     * @param email チェック対象のメールアドレス
     * @throws DomainException メールアドレスが重複している場合
     */
    public void execute(Email email) {

        // メールアドレスがnullなら重複チェック不要
        if (email == null) {
            return;
        }

        // リポジトリからメールアドレスで検索する
        userRepository.findByEmail(email.getValue())
                .ifPresent(user -> {
                    throw new DomainException("このメールアドレスは登録できません。");
                });
    }
}
