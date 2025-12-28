package com.example.keirekipro.usecase.user.notification;

import com.example.keirekipro.usecase.shared.notification.Notification;

/**
 * ユーザー削除通知
 *
 * @param to       送達先
 * @param username ユーザー名
 * @param siteName サイト名
 * @param siteUrl  サイトURL
 */
public record UserDeletedNotification(
        String to,
        String username,
        String siteName,
        String siteUrl) implements Notification {
}
