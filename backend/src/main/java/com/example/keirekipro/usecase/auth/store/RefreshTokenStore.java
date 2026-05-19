package com.example.keirekipro.usecase.auth.store;

import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import com.example.keirekipro.usecase.auth.dto.RefreshTokenInfo;

/**
 * リフレッシュトークンストア
 */
public interface RefreshTokenStore {

    /**
     * 不透明なリフレッシュトークンを発行し保存する
     *
     * @param userId ユーザーID
     * @param roles ロール
     * @param tokenVersion トークンバージョン
     * @return 発行されたリフレッシュトークン
     */
    String issue(UUID userId, Set<String> roles, long tokenVersion);

    /**
     * リフレッシュトークンに紐づく情報を取得する
     *
     * @param token リフレッシュトークン
     * @return リフレッシュトークン情報
     */
    Optional<RefreshTokenInfo> find(String token);

    /**
     * リフレッシュトークンを削除する
     *
     * @param token リフレッシュトークン
     */
    void remove(String token);

    /**
     * 指定ユーザーが保持するリフレッシュトークンを全て削除する
     *
     * @param userId ユーザーID
     */
    void removeAllByUser(UUID userId);
}
