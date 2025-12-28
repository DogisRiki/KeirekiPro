package com.example.keirekipro.usecase.auth.store;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

/**
 * 二段階認証コード保管ポート
 */
public interface TwoFactorAuthCodeStore {

    /**
     * 認証コードを保存する
     *
     * @param userId ユーザーID
     * @param code   認証コード
     * @param ttl    有効期限
     */
    void store(UUID userId, String code, Duration ttl);

    /**
     * 認証コードを取得する
     *
     * @param userId ユーザーID
     * @return 認証コード（存在しない場合はempty）
     */
    Optional<String> find(UUID userId);

    /**
     * 認証コードを削除する
     *
     * @param userId ユーザーID
     */
    void remove(UUID userId);
}
