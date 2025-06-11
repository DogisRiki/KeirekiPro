package com.example.keirekipro.domain.model.resume;

import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;

import lombok.Getter;

/**
 * ソーシャルリンク
 */
@Getter
public class SocialLink extends Entity {

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
    private SocialLink(String name, Link link) {
        super();
        this.name = name;
        this.link = link;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private SocialLink(UUID id, String name, Link link) {
        super(id);
        this.name = name;
        this.link = link;
    }

    /**
     * 新規構築用のファクトリーメソッド
     *
     * @param name ソーシャル名
     * @param link リンク
     * @return ソーシャルリンクエンティティ
     */
    public static SocialLink create(String name, Link link) {
        return new SocialLink(name, link);
    }

    /**
     * 再構築用のファクトリーメソッド
     *
     * @param id   識別子
     * @param name ソーシャル名
     * @param link リンク
     * @return ソーシャルリンクエンティティ
     */
    public static SocialLink reconstruct(UUID id, String name, Link link) {
        return new SocialLink(id, name, link);
    }

    /**
     * ソーシャル名を変更する
     *
     * @param name ソーシャル名
     * @return 変更後のソーシャルリンクエンティティ
     */
    public SocialLink changeName(String name) {
        return new SocialLink(this.id, name, this.link);
    }

    /**
     * リンクを変更する
     *
     * @param link リンク
     * @return 変更後のソーシャルリンクエンティティ
     */
    public SocialLink changeLink(Link link) {
        return new SocialLink(this.id, this.name, link);
    }
}
