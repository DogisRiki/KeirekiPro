package com.example.keirekipro.domain.service.user;

import java.util.Optional;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;

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
     * @param user チェック対象のユーザー
     * @return 重複チェック結果（trueなら重複）
     */
    public boolean execute(User user) {
        Email email = user.getEmail();
        // メールアドレスがnullなら重複チェック不要
        if (email == null) {
            return false;
        }
        // リポジトリからメールアドレスで検索する
        Optional<User> existing = userRepository.findByEmail(email.getValue());
        // 自分自身のIDは除外し、他ユーザーが見つかった場合 => 重複
        return existing
                .filter(u -> !u.getId().equals(user.getId()))
                .isPresent();
    }
}
