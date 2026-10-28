package com.example.keirekipro.usecase.auth.notification;

import com.example.keirekipro.usecase.shared.notification.Notification;

/**
 * メールアドレスの確認の通知
 *
 * @param to 送達先
 * @param verificationLink 確認のリンク
 * @param linkLifetime リンクの期限（「24時間」か「10分」）
 * @param siteName サイト名
 * @param siteUrl サイトURL
 */
public record EmailVerificationNotification(
        String to,
        String verificationLink,
        String linkLifetime,
        String siteName,
        String siteUrl) implements Notification {
}
