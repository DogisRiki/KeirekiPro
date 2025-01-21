package com.example.keirekipro.domain.model.resume;

import java.time.YearMonth;

import com.example.keirekipro.domain.shared.Notification;

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

    private Period(Notification notification, YearMonth startDate, YearMonth endDate, boolean isActive) {
        validate(notification, startDate, endDate, isActive);
        this.startDate = startDate;
        this.endDate = endDate;
        this.isActive = isActive;
    }

    /**
     * 生成メソッド
     *
     * @param notification 通知オブジェクト
     * @param startDate    開始年月
     * @param endDate      終了年月
     * @param isActive     継続中フラグ
     * @return 値オブジェクト
     */
    public static Period create(Notification notification, YearMonth startDate, YearMonth endDate, boolean isActive) {
        return new Period(notification, startDate, endDate, isActive);
    }

    private void validate(Notification notification, YearMonth startDate, YearMonth endDate, boolean isActive) {
        // 継続中でなければ、開始年月 <= 終了年月 の整合をチェック
        if (!isActive && isInvalidDateRange(startDate, endDate)) {
            notification.addError("endDate", "終了年月は開始年月より後の日付を指定してください。");
        }
        if (isInvalidEndDateForIsActive(endDate, isActive)) {
            notification.addError("endDate", "在籍中や担当中の場合は終了年月を指定しないでください。");
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
