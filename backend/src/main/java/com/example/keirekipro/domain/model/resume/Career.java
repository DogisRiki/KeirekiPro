package com.example.keirekipro.domain.model.resume;

import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;
import com.example.keirekipro.shared.ErrorCollector;

import lombok.Getter;

/**
 * 職歴
 */
@Getter
public class Career extends Entity {

    /**
     * 会社名
     */
    private final CompanyName companyName;

    /**
     * 期間
     */
    private final Period period;

    /**
     * 新規構築用のコンストラクタ
     */
    private Career(CompanyName companyName, Period period) {
        super();
        this.companyName = companyName;
        this.period = period;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private Career(UUID id, CompanyName companyName, Period period) {
        super(id);
        this.companyName = companyName;
        this.period = period;
    }

    /**
     * 新規構築用のファクトリーメソッド
     *
     * @param errorCollector エラー収集オブジェクト
     * @param companyName    会社名
     * @param period         期間
     * @return 職歴エンティティ
     */
    public static Career create(ErrorCollector errorCollector, CompanyName companyName, Period period) {
        validate(errorCollector, companyName, period);
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
    public static Career reconstruct(UUID id, CompanyName companyName, Period period) {
        return new Career(id, companyName, period);
    }

    /**
     * 会社名を変更する
     *
     * @param errorCollector エラー収集オブジェクト
     * @param companyName    会社名
     * @return 変更後の職歴エンティティ
     */
    public Career changeCompanyName(ErrorCollector errorCollector, CompanyName companyName) {
        validate(errorCollector, companyName, this.period);
        return new Career(this.id, companyName, this.period);
    }

    /**
     * 期間を変更する
     *
     * @param errorCollector エラー収集オブジェクト
     * @param period         期間
     * @return 変更後の職歴エンティティ
     */
    public Career changePeriod(ErrorCollector errorCollector, Period period) {
        validate(errorCollector, this.companyName, period);
        return new Career(this.id, this.companyName, period);
    }

    private static void validate(ErrorCollector errorCollector, CompanyName companyName, Period period) {
        if (companyName == null) {
            errorCollector.addError("companyName", "会社名は入力必須です。");
        }

        if (period == null) {
            errorCollector.addError("period", "期間は入力必須です。");
        }
    }
}
