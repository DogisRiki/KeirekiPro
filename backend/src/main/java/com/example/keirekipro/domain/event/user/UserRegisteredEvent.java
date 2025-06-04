package com.example.keirekipro.domain.event.user;

import java.util.UUID;

import com.example.keirekipro.domain.shared.event.AbstractDomainEvent;
import com.example.keirekipro.domain.shared.event.DomainEvent;

import lombok.Getter;

/**
 * ユーザー登録イベント
 */
@Getter
public class UserRegisteredEvent extends AbstractDomainEvent implements DomainEvent {

    private final UUID userId;
    private final String email;
    private final String username;

    /**
     * コンストラクタ
     *
     * @param userId   ユーザーID
     * @param email    メールアドレス
     * @param username ユーザー名
     */
    public UserRegisteredEvent(UUID userId, String email, String username) {
        super();
        this.userId = userId;
        this.email = email;
        this.username = username;
    }
}
