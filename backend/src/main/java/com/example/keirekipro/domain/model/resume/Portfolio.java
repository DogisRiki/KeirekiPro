package com.example.keirekipro.domain.model.resume;

import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;
import com.example.keirekipro.shared.Notification;

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
     * @param notification 通知オブジェクト
     * @param name         ポートフォリオ名
     * @param overview     ポートフォリオ概要
     * @param techStack    技術スタック
     * @param link         リンク
     * @return ポートフォリオエンティティ
     */
    public static Portfolio create(Notification notification, String name, String overview, String techStack,
            Link link) {
        validate(notification, name, overview, techStack, link);
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
     * @param notification 通知オブジェクト
     * @param name         ポートフォリオ名
     * @return 変更後のポートフォリオエンティティ
     */
    public Portfolio changeName(Notification notification, String name) {
        validate(notification, name, this.overview, this.techStack, this.link);
        return new Portfolio(this.id, name, this.overview, this.techStack, this.link);
    }

    /**
     * ポートフォリオ概要を変更する
     *
     * @param notification 通知オブジェクト
     * @param overview     ポートフォリオ概要
     * @return 変更後のポートフォリオエンティティ
     */
    public Portfolio changeOverview(Notification notification, String overview) {
        validate(notification, this.name, overview, this.techStack, this.link);
        return new Portfolio(this.id, this.name, overview, this.techStack, this.link);
    }

    /**
     * 技術スタックを変更する
     *
     * @param notification 通知オブジェクト
     * @param techStack    技術スタック
     * @return 変更後のポートフォリオエンティティ
     */
    public Portfolio changeTechStack(Notification notification, String techStack) {
        validate(notification, this.name, this.overview, techStack, this.link);
        return new Portfolio(this.id, this.name, this.overview, techStack, this.link);
    }

    /**
     * リンクを変更する
     *
     * @param notification 通知オブジェクト
     * @param link         リンク
     * @return 変更後のポートフォリオエンティティ
     */
    public Portfolio changeLink(Notification notification, Link link) {
        validate(notification, this.name, this.overview, this.techStack, link);
        return new Portfolio(this.id, this.name, this.overview, this.techStack, link);
    }

    private static void validate(Notification notification, String name, String overview, String techStack,
            Link link) {
        if (name == null || name.isBlank()) {
            notification.addError("name", "ポートフォリオ名は入力必須です。");
        } else if (name.length() > 50) {
            notification.addError("name", "ポートフォリオ名は50文字以内で入力してください。");
        }

        if (overview == null || overview.isBlank()) {
            notification.addError("overview", "ポートフォリオ概要は入力必須です。");
        } else if (overview.length() > 1000) {
            notification.addError("overview", "ポートフォリオ概要は1000文字以内で入力してください。");
        }

        if (techStack != null && techStack.length() > 1000) {
            notification.addError("techStack", "技術スタックは1000文字以内で入力してください。");
        }

        if (link == null) {
            notification.addError("link", "リンクは入力必須です。");
        }
    }
}
