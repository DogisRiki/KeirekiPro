package com.example.keirekipro.usecase.auth.notification;

import com.example.keirekipro.usecase.shared.notification.Notification;

/**
 * パスワードリセット通知
 *
 * @param to        送達先
 * @param resetLink リセットリンク
 * @param siteName  サイト名
 * @param siteUrl   サイトURL
 */
public record PasswordResetNotification(
        String to,
        String resetLink,
        String siteName,
        String siteUrl) implements Notification {
}
