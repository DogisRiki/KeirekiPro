package com.example.keirekipro.usecase.auth.notification;

import com.example.keirekipro.usecase.shared.notification.Notification;

/**
 * 二段階認証コード通知
 *
 * @param to       送達先
 * @param code     認証コード
 * @param siteName サイト名
 * @param siteUrl  サイトURL
 */
public record TwoFactorCodeNotification(
        String to,
        String code,
        String siteName,
        String siteUrl) implements Notification {
}
