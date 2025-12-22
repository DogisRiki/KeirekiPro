package com.example.keirekipro.domain.model.resume;

import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;
import com.example.keirekipro.shared.Notification;

import lombok.Getter;

/**
 * SNSプラットフォーム
 */
@Getter
public class SnsPlatform extends Entity {

    /**
     * プラットフォーム名
     */
    private final String name;

    /**
     * リンク
     */
    private final Link link;

    /**
     * 新規構築用のコンストラクタ
     */
    private SnsPlatform(String name, Link link) {
        super();
        this.name = name;
        this.link = link;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private SnsPlatform(UUID id, String name, Link link) {
        super(id);
        this.name = name;
        this.link = link;
    }

    /**
     * 新規構築用のファクトリーメソッド
     *
     * @param notification 通知オブジェクト
     * @param name         プラットフォーム名
     * @param link         リンク
     * @return SNSプラットフォームエンティティ
     */
    public static SnsPlatform create(Notification notification, String name, Link link) {
        validate(notification, name, link);
        return new SnsPlatform(name, link);
    }

    /**
     * 再構築用のファクトリーメソッド
     *
     * @param id   識別子
     * @param name プラットフォーム名
     * @param link リンク
     * @return SNSプラットフォームエンティティ
     */
    public static SnsPlatform reconstruct(UUID id, String name, Link link) {
        return new SnsPlatform(id, name, link);
    }

    /**
     * プラットフォーム名を変更する
     *
     * @param notification 通知オブジェクト
     * @param name         プラットフォーム名
     * @return 変更後のSNSプラットフォームエンティティ
     */
    public SnsPlatform changeName(Notification notification, String name) {
        validate(notification, name, this.link);
        return new SnsPlatform(this.id, name, this.link);
    }

    /**
     * リンクを変更する
     *
     * @param notification 通知オブジェクト
     * @param link         リンク
     * @return 変更後のSNSプラットフォームエンティティ
     */
    public SnsPlatform changeLink(Notification notification, Link link) {
        validate(notification, this.name, link);
        return new SnsPlatform(this.id, this.name, link);
    }

    private static void validate(Notification notification, String name, Link link) {
        if (name == null || name.isBlank()) {
            notification.addError("name", "プラットフォーム名は入力必須です。");
        } else if (name.length() > 50) {
            notification.addError("name", "プラットフォーム名は50文字以内で入力してください。");
        }

        if (link == null) {
            notification.addError("link", "リンクは入力必須です。");
        }
    }
}
