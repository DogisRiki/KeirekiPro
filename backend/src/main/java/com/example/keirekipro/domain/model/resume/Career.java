package com.example.keirekipro.domain.model.resume;

import com.example.keirekipro.domain.shared.Entity;

import lombok.Getter;

/**
 * 職歴
 */
@Getter
public class Career extends Entity {

    /**
     * 会社名
     */
    private final String companyName;

    /**
     * 期間
     */
    private final Period period;

    /**
     * 新規構築用のコンストラクタ
     */
    private Career(int orderNo, String companyName, Period period) {
        super(orderNo);
        this.companyName = companyName;
        this.period = period;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private Career(String id, int orderNo, String companyName, Period period) {
        super(id, orderNo);
        this.companyName = companyName;
        this.period = period;
    }

    /**
     * 新規構築用のメソッド
     *
     * @param orderNo     並び順
     * @param companyName 会社名
     * @param period      期間
     * @return 職歴エンティティ
     */
    public static Career create(int orderNo, String companyName, Period period) {
        return new Career(orderNo, companyName, period);
    }

    /**
     * 再構築用のメソッド
     *
     * @param id          識別子
     * @param orderNo     並び順
     * @param companyName 会社名
     * @param period      期間
     * @return 職歴エンティティ
     */
    public static Career reconstruct(String id, int orderNo, String companyName, Period period) {
        return new Career(id, orderNo, companyName, period);
    }

    /**
     * 会社名を変更する
     *
     * @param companyName 会社名
     * @return 変更後の職歴エンティティ
     */
    public Career changeCompanyName(String companyName) {
        return new Career(this.id, this.orderNo, companyName, this.period);
    }

    /**
     * 期間を変更する
     *
     * @param period 期間
     * @return 変更後の職歴エンティティ
     */
    public Career changePeriod(Period period) {
        return new Career(this.id, this.orderNo, this.companyName, period);
    }
}
