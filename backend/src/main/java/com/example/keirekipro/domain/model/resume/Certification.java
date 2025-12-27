package com.example.keirekipro.domain.model.resume;

import java.time.YearMonth;
import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;
import com.example.keirekipro.shared.ErrorCollector;

import lombok.Getter;

/**
 * 資格
 */
@Getter
public class Certification extends Entity {

    /**
     * 資格名
     */
    private final String name;

    /**
     * 取得年月
     */
    private final YearMonth date;

    /**
     * 新規構築用のコンストラクタ
     */
    private Certification(String name, YearMonth date) {
        super();
        this.name = name;
        this.date = date;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private Certification(UUID id, String name, YearMonth date) {
        super(id);
        this.name = name;
        this.date = date;
    }

    /**
     * 新規構築用のファクトリーメソッド
     *
     * @param errorCollector エラー収集オブジェクト
     * @param name           会社名
     * @param date           取得年月
     * @return 資格エンティティ
     */
    public static Certification create(ErrorCollector errorCollector, String name, YearMonth date) {
        validate(errorCollector, name, date);
        return new Certification(name, date);
    }

    /**
     * 再構築用のファクトリーメソッド
     *
     * @param id   識別子
     * @param name 会社名
     * @param date 取得年月
     * @return 資格エンティティ
     */
    public static Certification reconstruct(UUID id, String name, YearMonth date) {
        return new Certification(id, name, date);
    }

    /**
     * 資格名を変更する
     *
     * @param errorCollector エラー収集オブジェクト
     * @param name           資格名
     * @return 変更後の資格エンティティ
     */
    public Certification changeName(ErrorCollector errorCollector, String name) {
        validate(errorCollector, name, this.date);
        return new Certification(this.id, name, this.date);
    }

    /**
     * 取得年月を変更する
     *
     * @param errorCollector エラー収集オブジェクト
     * @param date           取得年月
     * @return 変更後の資格エンティティ
     */
    public Certification changeDate(ErrorCollector errorCollector, YearMonth date) {
        validate(errorCollector, this.name, date);
        return new Certification(this.id, this.name, date);
    }

    private static void validate(ErrorCollector errorCollector, String name, YearMonth date) {
        if (name == null || name.isBlank()) {
            errorCollector.addError("name", "資格名は入力必須です。");
        } else if (name.length() > 50) {
            errorCollector.addError("name", "資格名は50文字以内で入力してください。");
        }

        if (date == null) {
            errorCollector.addError("date", "取得年月は入力必須です。");
        }
    }
}
