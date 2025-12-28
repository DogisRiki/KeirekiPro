package com.example.keirekipro.infrastructure.event.user;

import com.example.keirekipro.domain.event.user.UserRegisteredEvent;
import com.example.keirekipro.shared.config.AppProperties;
import com.example.keirekipro.usecase.shared.notification.NotificationDispatcher;
import com.example.keirekipro.usecase.user.notification.UserRegisteredNotification;

import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー登録イベントリスナー
 */
@Component
@RequiredArgsConstructor
public class UserRegisteredEventListener {

    private final NotificationDispatcher notificationDispatcher;

    private final AppProperties properties;

    /**
     * イベントリスナー実行ハンドル
     *
     * @param event ユーザー登録イベント
     */
    @EventListener
    public void handle(UserRegisteredEvent event) {

        notificationDispatcher.dispatch(new UserRegisteredNotification(
                event.getEmail(),
                event.getUsername(),
                properties.getSiteName(),
                properties.getSiteUrl()));
    }
}
