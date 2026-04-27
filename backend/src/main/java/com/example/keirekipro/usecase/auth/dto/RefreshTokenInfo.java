package com.example.keirekipro.usecase.auth.dto;

import java.util.Set;
import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * リフレッシュトークン情報
 */
@Getter
@AllArgsConstructor
public class RefreshTokenInfo {

    /**
     * ユーザーID
     */
    private final UUID userId;

    /**
     * ロール
     */
    private final Set<String> roles;

    /**
     * トークンバージョン
     */
    private final long tokenVersion;
}
