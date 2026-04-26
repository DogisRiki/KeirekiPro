package com.example.keirekipro.usecase.auth.store;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.usecase.auth.dto.TwoFactorAuthChallenge;

/**
 * 二段階認証チャレンジトークン保管ポート
 */
public interface TwoFactorAuthChallengeStore {

    /**
     * チャレンジトークンを保存する
     *
     * @param token  チャレンジトークン
     * @param userId ユーザーID
     * @param ttl    有効期限
     */
    void store(String token, UUID userId, Duration ttl);

    /**
     * チャレンジトークンからチャレンジ情報を取得する
     *
     * @param token チャレンジトークン
     * @return チャレンジ情報（存在しない場合はempty）
     */
    Optional<TwoFactorAuthChallenge> find(String token);

    /**
     * 失敗試行回数を加算する
     *
     * @param token チャレンジトークン
     * @return 加算後の試行回数
     */
    int incrementAttempts(String token);

    /**
     * チャレンジトークンを削除する
     *
     * @param token チャレンジトークン
     */
    void remove(String token);
}
