package com.example.keirekipro.domain.model.resume;

import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;
import com.example.keirekipro.shared.Notification;

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
     * @param notification 通知オブジェクト
     * @param companyName  会社名
     * @param period       期間
     * @return 職歴エンティティ
     */
    public static Career create(Notification notification, CompanyName companyName, Period period) {
        validate(notification, companyName, period);
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
     * @param notification 通知オブジェクト
     * @param companyName  会社名
     * @return 変更後の職歴エンティティ
     */
    public Career changeCompanyName(Notification notification, CompanyName companyName) {
        validate(notification, companyName, this.period);
        return new Career(this.id, companyName, this.period);
    }

    /**
     * 期間を変更する
     *
     * @param notification 通知オブジェクト
     * @param period       期間
     * @return 変更後の職歴エンティティ
     */
    public Career changePeriod(Notification notification, Period period) {
        validate(notification, this.companyName, period);
        return new Career(this.id, this.companyName, period);
    }

    private static void validate(Notification notification, CompanyName companyName, Period period) {
        if (companyName == null) {
            notification.addError("companyName", "会社名は入力必須です。");
        }

        if (period == null) {
            notification.addError("period", "期間は入力必須です。");
        }
    }
}
