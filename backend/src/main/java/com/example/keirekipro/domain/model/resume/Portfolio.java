package com.example.keirekipro.domain.model.resume;

import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;

import lombok.Getter;

/**
 * ポートフォリオ
 */
@Getter
public class Portfolio extends Entity {

    /**
     * ポートフォリオ名
     */
    private final String name;

    /**
     * ポートフォリオ概要
     */
    private final String overview;

    /**
     * 技術スタック
     */
    private final String techStack;

    /**
     * リンク
     */
    private final Link link;

    /**
     * 新規構築用のコンストラクタ
     */
    private Portfolio(String name, String overview, String techStack, Link link) {
        super();
        this.name = name;
        this.overview = overview;
        this.techStack = techStack;
        this.link = link;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private Portfolio(UUID id, String name, String overview, String techStack, Link link) {
        super(id);
        this.name = name;
        this.overview = overview;
        this.techStack = techStack;
        this.link = link;
    }

    /**
     * 新規構築用のファクトリーメソッド
     *
     * @param name      ポートフォリオ名
     * @param overview  ポートフォリオ概要
     * @param techStack 技術スタック
     * @param link      リンク
     * @return ポートフォリオエンティティ
     */
    public static Portfolio create(String name, String overview, String techStack, Link link) {
        return new Portfolio(name, overview, techStack, link);
    }

    /**
     * 再構築用のファクトリーメソッド
     *
     * @param id        識別子
     * @param name      ポートフォリオ名
     * @param overview  ポートフォリオ概要
     * @param techStack 技術スタック
     * @param link      リンク
     * @return ポートフォリオエンティティ
     */
    public static Portfolio reconstruct(UUID id, String name, String overview, String techStack,
            Link link) {
        return new Portfolio(id, name, overview, techStack, link);
    }

    /**
     * ポートフォリオ名を変更する
     *
     * @param name ポートフォリオ名
     * @return 変更後のポートフォリオエンティティ
     */
    public Portfolio changeName(String name) {
        return new Portfolio(this.id, name, this.overview, this.techStack, this.link);
    }

    /**
     * ポートフォリオ概要を変更する
     *
     * @param overview ポートフォリオ概要
     * @return 変更後のポートフォリオエンティティ
     */
    public Portfolio changeOverview(String overview) {
        return new Portfolio(this.id, this.name, overview, this.techStack, this.link);
    }

    /**
     * 技術スタックを変更する
     *
     * @param techStack 技術スタック
     * @return 変更後のポートフォリオエンティティ
     */
    public Portfolio changeTechStack(String techStack) {
        return new Portfolio(this.id, this.name, this.overview, techStack, this.link);
    }

    /**
     * リンクを変更する
     *
     * @param link リンク
     * @return 変更後のポートフォリオエンティティ
     */
    public Portfolio changeLink(Link link) {
        return new Portfolio(this.id, this.name, this.overview, this.techStack, link);
    }
}
