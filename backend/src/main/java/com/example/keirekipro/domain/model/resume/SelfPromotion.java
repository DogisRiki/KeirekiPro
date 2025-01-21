package com.example.keirekipro.domain.model.resume;

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
    private SelfPromotion(int orderNo, String title, String content) {
        super(orderNo);
        this.title = title;
        this.content = content;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private SelfPromotion(String id, int orderNo, String title, String content) {
        super(id, orderNo);
        this.title = title;
        this.content = content;
    }

    /**
     * 新規構築用のファクトリーメソッド
     *
     * @param orderNo 並び順
     * @param title   タイトル
     * @param content コンテンツ
     * @return 自己PRエンティティ
     */
    public static SelfPromotion create(int orderNo, String title, String content) {
        return new SelfPromotion(orderNo, title, content);
    }

    /**
     * 再構築用のファクトリーメソッド
     *
     * @param id      識別子
     * @param orderNo 並び順
     * @param title   タイトル
     * @param content コンテンツ
     * @return 自己PRエンティティ
     */
    public static SelfPromotion reconstruct(String id, int orderNo, String title, String content) {
        return new SelfPromotion(id, orderNo, title, content);
    }

    /**
     * タイトルを変更する
     *
     * @param title タイトル
     * @return 変更後の自己PRエンティティ
     */
    public SelfPromotion changeTitle(String title) {
        return new SelfPromotion(this.id, this.orderNo, title, this.content);
    }

    /**
     * コンテンツを変更する
     *
     * @param content コンテンツ
     * @return 変更後の自己PRエンティティ
     */
    public SelfPromotion changeContent(String content) {
        return new SelfPromotion(this.id, this.orderNo, this.title, content);
    }
}
