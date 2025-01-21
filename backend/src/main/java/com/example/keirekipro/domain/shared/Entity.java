package com.example.keirekipro.domain.shared;

import java.io.Serializable;
import java.util.UUID;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * エンティティの抽象クラス
 *
 * @param <T> 識別子の型
 */
@Getter
@EqualsAndHashCode(onlyExplicitlyIncluded = true)
public abstract class Entity implements Serializable {

    /**
     * 識別子
     */
    @EqualsAndHashCode.Include
    protected final String id;

    /**
     * 並び順
     */
    protected int orderNo;

    /**
     * 新規構築用のコンストラクター
     *
     * @param orderNo 並び順
     */
    protected Entity(int orderNo) {
        this(UUID.randomUUID().toString(), orderNo);
    }

    /**
     * 再構築用のコンストラクター
     *
     * @param id      識別子
     * @param orderNo 並び順
     */
    protected Entity(String id, int orderNo) {
        this.id = id;
        this.orderNo = orderNo;
    }

    /**
     * 並び順を変更する
     *
     * @param orderNo 並び順
     */
    public void changeOrderNo(int orderNo) {
        this.orderNo = orderNo;
    }
}
