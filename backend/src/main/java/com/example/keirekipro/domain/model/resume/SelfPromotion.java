package com.example.keirekipro.domain.model.resume;

import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;

import lombok.Getter;

/**
 * 自己PR
 */
@Getter
public class SelfPromotion extends Entity {

    /**
     * タイトル
     */
    private final String title;

    /**
     * コンテンツ
     */
    private final String content;

    /**
     * 新規構築用のコンストラクタ
     */
    private SelfPromotion(String title, String content) {
        super();
        this.title = title;
        this.content = content;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private SelfPromotion(UUID id, String title, String content) {
        super(id);
        this.title = title;
        this.content = content;
    }

    /**
     * 新規構築用のファクトリーメソッド
     *
     * @param title   タイトル
     * @param content コンテンツ
     * @return 自己PRエンティティ
     */
    public static SelfPromotion create(String title, String content) {
        return new SelfPromotion(title, content);
    }

    /**
     * 再構築用のファクトリーメソッド
     *
     * @param id      識別子
     * @param title   タイトル
     * @param content コンテンツ
     * @return 自己PRエンティティ
     */
    public static SelfPromotion reconstruct(UUID id, String title, String content) {
        return new SelfPromotion(id, title, content);
    }

    /**
     * タイトルを変更する
     *
     * @param title タイトル
     * @return 変更後の自己PRエンティティ
     */
    public SelfPromotion changeTitle(String title) {
        return new SelfPromotion(this.id, title, this.content);
    }

    /**
     * コンテンツを変更する
     *
     * @param content コンテンツ
     * @return 変更後の自己PRエンティティ
     */
    public SelfPromotion changeContent(String content) {
        return new SelfPromotion(this.id, this.title, content);
    }
}
