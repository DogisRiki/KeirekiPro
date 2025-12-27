package com.example.keirekipro.domain.model.resume;

import java.time.YearMonth;

import com.example.keirekipro.shared.ErrorCollector;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * 期間
 */
@Getter
@EqualsAndHashCode
public class Period {

    /**
     * 開始年月
     */
    private final YearMonth startDate;

    /**
     * 終了年月
     */
    private final YearMonth endDate;

    /**
     * 継続中フラグ
     */
    private final boolean isActive;

    private Period(ErrorCollector errorCollector, YearMonth startDate, YearMonth endDate, boolean isActive) {
        validate(errorCollector, startDate, endDate, isActive);
        this.startDate = startDate;
        this.endDate = endDate;
        this.isActive = isActive;
    }

    /**
     * ファクトリーメソッド
     *
     * @param errorCollector エラー収集オブジェクト
     * @param startDate      開始年月
     * @param endDate        終了年月
     * @param isActive       継続中フラグ
     * @return 値オブジェクト
     */
    public static Period create(ErrorCollector errorCollector, YearMonth startDate, YearMonth endDate,
            boolean isActive) {
        return new Period(errorCollector, startDate, endDate, isActive);
    }

    private void validate(ErrorCollector errorCollector, YearMonth startDate, YearMonth endDate, boolean isActive) {
        // 開始年月は必須
        if (startDate == null) {
            errorCollector.addError("startDate", "開始年月は入力必須です。");
            return;
        }

        // 継続中でない場合は終了年月も必須
        if (!isActive && endDate == null) {
            errorCollector.addError("endDate", "終了年月は入力必須です。");
            return;
        }

        // 継続中でなければ、開始年月 <= 終了年月 の整合をチェック
        if (!isActive && endDate != null && isInvalidDateRange(startDate, endDate)) {
            errorCollector.addError("endDate", "終了年月は開始年月より後の日付を指定してください。");
        }
        if (isInvalidEndDateForIsActive(endDate, isActive)) {
            errorCollector.addError("endDate", "継続中の場合、終了年月を設定できません。");
        }
    }

    /**
     * 開始年月が終了年月より大きいかを検証
     *
     * @param startDate 開始年月
     * @param endDate   終了年月
     * @return 検証結果
     */
    private boolean isInvalidDateRange(YearMonth startDate, YearMonth endDate) {
        return startDate.isAfter(endDate);
    }

    /**
     * 継続中である場合、終了年月が指定されていないかを検証
     *
     * @param endDate  終了年月
     * @param isActive 継続中フラグ
     * @return 検証結果
     */
    private boolean isInvalidEndDateForIsActive(YearMonth endDate, boolean isActive) {
        return isActive && endDate != null;
    }
}
