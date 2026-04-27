package com.example.keirekipro.usecase.auth.session;

import java.util.UUID;

import com.example.keirekipro.usecase.auth.store.RefreshTokenStore;
import com.example.keirekipro.usecase.auth.store.UserTokenVersionStore;

import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * 認証セッション無効化サービス
 * トークンバージョンを加算し、該当ユーザーのリフレッシュトークンを全て削除する
 */
@Component
@RequiredArgsConstructor
public class AuthSessionInvalidator {

    private final UserTokenVersionStore userTokenVersionStore;

    private final RefreshTokenStore refreshTokenStore;

    /**
     * 指定ユーザーの認証セッションを無効化する
     *
     * @param userId ユーザーID
     */
    public void invalidate(UUID userId) {
        userTokenVersionStore.increment(userId);
        refreshTokenStore.removeAllByUser(userId);
    }
}
