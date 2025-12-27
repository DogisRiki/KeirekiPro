package com.example.keirekipro.domain.model.resume;

import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;
import com.example.keirekipro.shared.ErrorCollector;

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
     * @param errorCollector エラー収集オブジェクト
     * @param title          タイトル
     * @param content        コンテンツ
     * @return 自己PRエンティティ
     */
    public static SelfPromotion create(ErrorCollector errorCollector, String title, String content) {
        validate(errorCollector, title, content);
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
     * @param errorCollector エラー収集オブジェクト
     * @param title          タイトル
     * @return 変更後の自己PRエンティティ
     */
    public SelfPromotion changeTitle(ErrorCollector errorCollector, String title) {
        validate(errorCollector, title, this.content);
        return new SelfPromotion(this.id, title, this.content);
    }

    /**
     * コンテンツを変更する
     *
     * @param errorCollector エラー収集オブジェクト
     * @param content        コンテンツ
     * @return 変更後の自己PRエンティティ
     */
    public SelfPromotion changeContent(ErrorCollector errorCollector, String content) {
        validate(errorCollector, this.title, content);
        return new SelfPromotion(this.id, this.title, content);
    }

    private static void validate(ErrorCollector errorCollector, String title, String content) {
        if (title == null || title.isBlank()) {
            errorCollector.addError("title", "タイトルは入力必須です。");
        } else if (title.length() > 50) {
            errorCollector.addError("title", "タイトルは50文字以内で入力してください。");
        }

        if (content == null || content.isBlank()) {
            errorCollector.addError("content", "コンテンツは入力必須です。");
        } else if (content.length() > 1000) {
            errorCollector.addError("content", "コンテンツは1000文字以内で入力してください。");
        }
    }
}
