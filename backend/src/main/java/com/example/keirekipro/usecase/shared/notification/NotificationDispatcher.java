package com.example.keirekipro.usecase.shared.notification;

/**
 * 通知送達ポート
 */
public interface NotificationDispatcher {

    /**
     * 通知を送達する
     *
     * @param notification 通知
     */
    void dispatch(Notification notification);
}
