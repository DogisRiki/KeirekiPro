package com.example.keirekipro.domain.shared.event;

/**
 * ドメインイベントパブリッシャーのインターフェース
 */
public interface DomainEventPublisher {

    /**
     * ドメインイベントを発火する
     *
     * @param event 発火するイベント
     */
    void publish(DomainEvent event);
}
