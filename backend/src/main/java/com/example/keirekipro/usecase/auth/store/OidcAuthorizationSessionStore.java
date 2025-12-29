package com.example.keirekipro.usecase.auth.store;

import java.time.Duration;
import java.util.Optional;

import com.example.keirekipro.usecase.auth.oidc.OidcAuthorizationSession;

/**
 * OIDC認可セッション保管ストア
 */
public interface OidcAuthorizationSessionStore {

    /**
     * 認可セッションを保存する
     *
     * @param state        state値
     * @param provider     プロバイダー名
     * @param codeVerifier code_verifier
     * @param ttl          有効期限
     */
    void store(String state, String provider, String codeVerifier, Duration ttl);

    /**
     * stateから認可セッションを取得する
     *
     * @param state state値
     * @return 認可セッション（存在しない場合はOptional.empty()）
     */
    Optional<OidcAuthorizationSession> find(String state);

    /**
     * stateに紐づく認可セッションを削除する
     *
     * @param state state値
     */
    void remove(String state);
}
