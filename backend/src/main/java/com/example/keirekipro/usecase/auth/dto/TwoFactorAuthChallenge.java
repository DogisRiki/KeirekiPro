package com.example.keirekipro.usecase.auth.dto;

import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 二段階認証チャレンジ情報
 */
@Getter
@Setter
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class TwoFactorAuthChallenge {

    /**
     * ユーザーID
     */
    private UUID userId;

    /**
     * 失敗試行回数
     */
    private int attempts;
}
