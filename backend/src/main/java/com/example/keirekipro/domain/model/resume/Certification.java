package com.example.keirekipro.domain.model.resume;

import java.time.YearMonth;

import com.example.keirekipro.domain.shared.Entity;

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
    private Certification(int orderNo, String name, YearMonth date) {
        super(orderNo);
        this.name = name;
        this.date = date;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private Certification(String id, int orderNo, String name, YearMonth date) {
        super(id, orderNo);
        this.name = name;
        this.date = date;
    }

    /**
     * 新規構築用のメソッド
     *
     * @param orderNo 並び順
     * @param name    会社名
     * @param date    取得年月
     * @return 資格エンティティ
     */
    public static Certification create(int orderNo, String name, YearMonth date) {
        return new Certification(orderNo, name, date);
    }

    /**
     * 再構築用のメソッド
     *
     * @param id      識別子
     * @param orderNo 並び順
     * @param name    会社名
     * @param date    取得年月
     * @return 資格エンティティ
     */
    public static Certification reconstruct(String id, int orderNo, String name, YearMonth date) {
        return new Certification(id, orderNo, name, date);
    }

    /**
     * 資格名を変更する
     *
     * @param name 資格名
     * @return 変更後の資格エンティティ
     */
    public Certification changeName(String name) {
        return new Certification(this.id, this.orderNo, name, this.date);
    }

    /**
     * 取得年月を変更する
     *
     * @param date 取得年月
     * @return 変更後の資格エンティティ
     */
    public Certification changeDate(YearMonth date) {
        return new Certification(this.id, this.orderNo, this.name, date);
    }
}
