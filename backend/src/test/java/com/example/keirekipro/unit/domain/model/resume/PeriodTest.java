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
        Period period = Period.create(notification, YearMonth.of(2025, 1), YearMonth.of(2025, 2), false);

        assertThat(period).isNotNull();
        assertThat(period.getStartDate()).isEqualTo(YearMonth.of(2025, 1));
        assertThat(period.getEndDate()).isEqualTo(YearMonth.of(2025, 2));
        assertThat(period.isActive()).isFalse();
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("正常な値（継続中フラグtrue）でインスタンス化する")
    void test2() {
        Period period = Period.create(notification, YearMonth.of(2025, 1), null, true);

        assertThat(period).isNotNull();
        assertThat(period.getStartDate()).isEqualTo(YearMonth.of(2025, 1));
        assertThat(period.getEndDate()).isNull();
        assertThat(period.isActive()).isTrue();
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("開始年月を終了年月より大きい値でインスタンス化する（継続中フラグfalse）")
    void test3() {
        Period period = Period.create(notification, YearMonth.of(2025, 3), YearMonth.of(2025, 2), false);

        assertThat(period).isNotNull();
        // isInvalidDateRange()に対応するエラーメッセージが登録される
        verify(notification, times(1)).addError(
                eq("endDate"),
                eq("終了年月は開始年月より後の日付を指定してください。"));
        // 継続中に対するエラーメッセージは登録されない
        verify(notification, never()).addError(
                eq("endDate"),
                eq("継続中の場合、終了年月を設定できません。"));
    }

    @Test
    @DisplayName("継続中であれば開始年月を終了年月より大きい値でインスタンス化してもisInvalidDateRange()はスルーされる")
    void test4() {
        Period period = Period.create(notification, YearMonth.of(2025, 3), YearMonth.of(2025, 2), true);

        assertThat(period).isNotNull();
        // isInvalidDateRange()に対応するエラーメッセージが登録されない
        verify(notification, never()).addError(
                eq("endDate"),
                eq("終了年月は開始年月より後の日付を指定してください。"));
        // 継続中に対するエラーメッセージが登録される
        verify(notification, times(1)).addError(
                eq("endDate"),
                eq("継続中の場合、終了年月を設定できません。"));
    }

    @Test
    @DisplayName("継続中かつ終了年月を非nullの値でインスタンス化する")
    void test5() {
        Period period = Period.create(notification, YearMonth.of(2025, 1), YearMonth.of(2025, 2), true);

        assertThat(period).isNotNull();
        // 継続中に対するエラーメッセージが登録される
        verify(notification, times(1)).addError(
                eq("endDate"),
                eq("継続中の場合、終了年月を設定できません。"));
        // isInvalidDateRange()に対応するエラーメッセージが登録されない
        verify(notification, never()).addError(
                eq("endDate"),
                eq("終了年月は開始年月より後の日付を指定してください。"));
    }

    @Test
    @DisplayName("開始年月がnullの状態でインスタンス化する")
    void test6() {
        Period period = Period.create(notification, null, YearMonth.of(2025, 2), false);

        assertThat(period).isNotNull();
        verify(notification, times(1)).addError(
                eq("startDate"),
                eq("開始年月は入力必須です。"));
        // 終了年月に対するエラーは登録されない（開始年月エラーで打ち切り）
        verify(notification, never()).addError(eq("endDate"), anyString());
    }

    @Test
    @DisplayName("継続中フラグfalseかつ終了年月がnullの状態でインスタンス化する")
    void test7() {
        Period period = Period.create(notification, YearMonth.of(2025, 1), null, false);

        assertThat(period).isNotNull();
        verify(notification, times(1)).addError(
                eq("endDate"),
                eq("終了年月は入力必須です。"));
        // 開始年月に対するエラーは登録されない
        verify(notification, never()).addError(eq("startDate"), anyString());
    }
}
