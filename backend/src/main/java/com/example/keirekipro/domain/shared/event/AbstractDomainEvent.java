package com.example.keirekipro.domain.shared.event;

import java.time.Instant;
import java.util.UUID;

/**
 * ドメインイベント基底クラス
 */
public abstract class AbstractDomainEvent {

    /**
     * イベントID
     */
    private final UUID eventId;

    /**
     * イベント発生日時
     */
    private final Instant occurredOn;

    /**
     * コンストラクタ
     */
    protected AbstractDomainEvent() {
        this.eventId = UUID.randomUUID();
        this.occurredOn = Instant.now();
    }

    public UUID getEventId() {
        return eventId;
    }

    public Instant getOccurredOn() {
        return occurredOn;
    }
}
