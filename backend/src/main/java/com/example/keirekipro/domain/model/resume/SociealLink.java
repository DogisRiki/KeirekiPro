package com.example.keirekipro.domain.model.resume;

import com.example.keirekipro.domain.shared.Entity;

import lombok.Getter;

/**
 * ソーシャルリンク
 */
@Getter
public class SociealLink extends Entity {

    /**
     * ソーシャル名
     */
    private final String name;

    /**
     * リンク
     */
    private final Link link;

    /**
     * 新規構築用のコンストラクタ
     */
    private SociealLink(int orderNo, String name, Link link) {
        super(orderNo);
        this.name = name;
        this.link = link;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private SociealLink(String id, int orderNo, String name, Link link) {
        super(id, orderNo);
        this.name = name;
        this.link = link;
    }

    /**
     * 新規構築用のファクトリーメソッド
     *
     * @param orderNo 並び順
     * @param name    ソーシャル名
     * @param link    リンク
     * @return ソーシャルリンクエンティティ
     */
    public static SociealLink create(int orderNo, String name, Link link) {
        return new SociealLink(orderNo, name, link);
    }

    /**
     * 再構築用のファクトリーメソッド
     *
     * @param id      識別子
     * @param orderNo 並び順
     * @param name    ソーシャル名
     * @param link    リンク
     * @return ソーシャルリンクエンティティ
     */
    public static SociealLink reconstruct(String id, int orderNo, String name, Link link) {
        return new SociealLink(id, orderNo, name, link);
    }

    /**
     * ソーシャル名を変更する
     *
     * @param name ソーシャル名
     * @return 変更後のソーシャルリンクエンティティ
     */
    public SociealLink changeName(String name) {
        return new SociealLink(this.id, this.orderNo, name, this.link);
    }

    /**
     * リンクを変更する
     *
     * @param link リンク
     * @return 変更後のソーシャルリンクエンティティ
     */
    public SociealLink changeLink(Link link) {
        return new SociealLink(this.id, this.orderNo, this.name, link);
    }
}
