package com.example.keirekipro.domain.model.resume;

import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;
import com.example.keirekipro.shared.Notification;

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
     * @param notification 通知オブジェクト
     * @param name         ソーシャル名
     * @param link         リンク
     * @return ソーシャルリンクエンティティ
     */
    public static SocialLink create(Notification notification, String name, Link link) {
        validate(notification, name, link);
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
     * @param notification 通知オブジェクト
     * @param name         ソーシャル名
     * @return 変更後のソーシャルリンクエンティティ
     */
    public SocialLink changeName(Notification notification, String name) {
        validate(notification, name, this.link);
        return new SocialLink(this.id, name, this.link);
    }

    /**
     * リンクを変更する
     *
     * @param notification 通知オブジェクト
     * @param link         リンク
     * @return 変更後のソーシャルリンクエンティティ
     */
    public SocialLink changeLink(Notification notification, Link link) {
        validate(notification, this.name, link);
        return new SocialLink(this.id, this.name, link);
    }

    private static void validate(Notification notification, String name, Link link) {
        if (name == null || name.isBlank()) {
            notification.addError("name", "ソーシャル名は入力必須です。");
        } else if (name.length() > 50) {
            notification.addError("name", "ソーシャル名は50文字以内で入力してください。");
        }

        if (link == null) {
            notification.addError("link", "リンクは入力必須です。");
        }
    }
}
