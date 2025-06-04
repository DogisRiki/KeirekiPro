package com.example.keirekipro.infrastructure.shared.event;

import com.example.keirekipro.domain.shared.event.DomainEvent;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;

import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * SpringのApplicationEventPublisherを使ったドメインイベント発行実装
 */
@Component
@RequiredArgsConstructor
public class SpringDomainEventPublisher implements DomainEventPublisher {

    private final ApplicationEventPublisher applicationEventPublisher;

    @Override
    public void publish(DomainEvent event) {
        applicationEventPublisher.publishEvent(event);
    }
}
