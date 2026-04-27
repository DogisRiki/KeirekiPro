package com.example.keirekipro.usecase.auth.store;

import java.util.UUID;

/**
 * ユーザートークンバージョンストア
 */
public interface UserTokenVersionStore {

    /**
     * 指定ユーザーのトークンバージョンを取得する
     *
     * @param userId ユーザーID
     * @return トークンバージョン
     */
    long get(UUID userId);

    /**
     * 指定ユーザーのトークンバージョンをインクリメントする
     *
     * @param userId ユーザーID
     */
    void increment(UUID userId);

    /**
     * 指定ユーザーのトークンバージョンを初期化する
     *
     * @param userId ユーザーID
     */
    void initialize(UUID userId);
}
