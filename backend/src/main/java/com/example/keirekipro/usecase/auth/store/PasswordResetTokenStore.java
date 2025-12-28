package com.example.keirekipro.usecase.auth.store;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

/**
 * パスワードリセットトークン保管ポート
 */
public interface PasswordResetTokenStore {

    /**
     * トークンを保存する
     *
     * @param token  トークン
     * @param userId ユーザーID
     * @param ttl    有効期限
     */
    void store(String token, UUID userId, Duration ttl);

    /**
     * トークンからユーザーIDを取得する
     *
     * @param token トークン
     * @return ユーザーID（存在しない場合はempty）
     */
    Optional<UUID> findUserId(String token);

    /**
     * トークンを削除する
     *
     * @param token トークン
     */
    void remove(String token);
}
