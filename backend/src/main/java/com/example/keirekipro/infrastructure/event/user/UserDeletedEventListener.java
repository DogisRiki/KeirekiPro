package com.example.keirekipro.infrastructure.event.user;

import com.example.keirekipro.domain.event.user.UserDeletedEvent;
import com.example.keirekipro.shared.config.AppProperties;
import com.example.keirekipro.usecase.shared.notification.NotificationDispatcher;
import com.example.keirekipro.usecase.user.notification.UserDeletedNotification;

import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー削除イベントリスナー
 */
@Component
@RequiredArgsConstructor
public class UserDeletedEventListener {

    private final NotificationDispatcher notificationDispatcher;

    private final AppProperties properties;

    /**
     * イベントリスナー実行ハンドル
     *
     * @param event ユーザー削除イベント
     */
    @EventListener
    public void handle(UserDeletedEvent event) {

        notificationDispatcher.dispatch(new UserDeletedNotification(
                event.getEmail(),
                event.getUsername(),
                properties.getSiteName(),
                properties.getSiteUrl()));
    }
}
