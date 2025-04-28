package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import java.time.YearMonth;

import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class PeriodTest {

    @Mock
    private Notification notification;

    @Test
    @DisplayName("正常な値（継続中フラグfalse）でインスタンス化する")
    void test1() {
        Period period = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), false);

        assertThat(period).isNotNull();
        assertThat(period.getStartDate()).isEqualTo(YearMonth.of(2025, 01));
        assertThat(period.getEndDate()).isEqualTo(YearMonth.of(2025, 02));
        assertThat(period.isActive()).isFalse();
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("正常な値（継続中フラグtrue）でインスタンス化する")
    void test2() {
        Period period = Period.create(notification, YearMonth.of(2025, 01), null, true);

        assertThat(period).isNotNull();
        assertThat(period.getStartDate()).isEqualTo(YearMonth.of(2025, 01));
        assertThat(period.getEndDate()).isNull();
        assertThat(period.isActive()).isTrue();
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("開始年月を終了年月より大きい値でインスタンス化する")
    void test3() {
        Period period = Period.create(notification, YearMonth.of(2025, 03), YearMonth.of(2025, 02), false);

        assertThat(period).isNotNull();
        // isInvalidDateRange()に対応するエラーメッセージが登録される
        verify(notification, times(
                1)).addError(
                        eq("endDate"),
                        eq("終了年月は開始年月より後の日付を指定してください。"));
        // isInvalidEndDateForIsActive()に対応するエラーメッセージが登録されない
        verify(notification, never()).addError("endDate", "在籍中や担当中の場合は終了年月を指定しないでください。");
    }

    @Test
    @DisplayName("継続中であれば開始年月を終了年月より大きい値でインスタンス化してもisInvalidDateRange()はスルーされる")
    void test4() {
        Period period = Period.create(notification, YearMonth.of(2025, 03), YearMonth.of(2025, 02), true);

        assertThat(period).isNotNull();
        // isInvalidDateRange()に対応するエラーメッセージが登録されない
        verify(notification, never()).addError("endDate", "終了年月は開始年月より後の日付を指定してください。");
        // isInvalidEndDateForIsActive()に対応するエラーメッセージが登録される
        verify(notification, times(1)).addError(
                eq("endDate"),
                eq("在籍中や担当中の場合は終了年月を指定しないでください。"));
    }

    @Test
    @DisplayName("継続中かつ終了年月を非nullの値でインスタンス化する")
    void test5() {
        Period period = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), true);

        assertThat(period).isNotNull();
        // isInvalidEndDateForIsActive()に対応するエラーメッセージが登録される
        verify(notification, times(
                1)).addError(
                        eq("endDate"),
                        eq("在籍中や担当中の場合は終了年月を指定しないでください。"));
        // isInvalidDateRange()に対応するエラーメッセージが登録されない
        verify(notification, never()).addError("endDate", "終了年月は開始年月より後の日付を指定してください。");
    }
}
