package com.example.keirekipro.domain.model.resume;

import java.util.UUID;

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
    private Career(String companyName, Period period) {
        super();
        this.companyName = companyName;
        this.period = period;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private Career(UUID id, String companyName, Period period) {
        super(id);
        this.companyName = companyName;
        this.period = period;
    }

    /**
     * 新規構築用のファクトリーメソッド
     *
     * @param companyName 会社名
     * @param period      期間
     * @return 職歴エンティティ
     */
    public static Career create(String companyName, Period period) {
        return new Career(companyName, period);
    }

    /**
     * 再構築用のファクトリーメソッド
     *
     * @param id          識別子
     * @param companyName 会社名
     * @param period      期間
     * @return 職歴エンティティ
     */
    public static Career reconstruct(UUID id, String companyName, Period period) {
        return new Career(id, companyName, period);
    }

    /**
     * 会社名を変更する
     *
     * @param companyName 会社名
     * @return 変更後の職歴エンティティ
     */
    public Career changeCompanyName(String companyName) {
        return new Career(this.id, companyName, this.period);
    }

    /**
     * 期間を変更する
     *
     * @param period 期間
     * @return 変更後の職歴エンティティ
     */
    public Career changePeriod(Period period) {
        return new Career(this.id, this.companyName, period);
    }
}
