package com.example.keirekipro.domain.shared;

import java.io.Serializable;
import java.util.UUID;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * エンティティの抽象クラス
 */
@Getter
@EqualsAndHashCode(onlyExplicitlyIncluded = true)
public abstract class Entity implements Serializable {

    /**
     * 識別子
     */
    @EqualsAndHashCode.Include
    protected final UUID id;

    /**
     * 新規構築用のコンストラクター
     */
    protected Entity() {
        this(UUID.randomUUID());
    }

    /**
     * 再構築用のコンストラクター
     *
     * @param id 識別子
     */
    protected Entity(UUID id) {
        this.id = id;
    }
}
