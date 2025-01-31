package com.example.keirekipro.domain.resume;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import java.time.YearMonth;

import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.shared.Notification;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class PeriodTest {

    @Mock
    private Notification notification;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    @DisplayName("正常な値（継続中フラグfalse）でインスタンス化する")
    void test1() {
        Period period = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), false);
        // インスタンスがnullでない。
        assertNotNull(period);
        // 開始年月が正しい値である。
        assertEquals(YearMonth.of(2025, 01), period.getStartDate());
        // 終了年月が正しい値である。
        assertEquals(YearMonth.of(2025, 02), period.getEndDate());
        // 継続中フラグが正しい値である。
        assertFalse(period.isActive());
        // notification.addError()が一度も呼ばれていない。
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("正常な値（継続中フラグtrue）でインスタンス化する")
    void test2() {
        Period period = Period.create(notification, YearMonth.of(2025, 01), null, true);
        // インスタンスがnullでない。
        assertNotNull(period);
        // 開始年月が正しい値である。
        assertEquals(YearMonth.of(2025, 01), period.getStartDate());
        // 終了年月が正しい値である。
        assertNull(period.getEndDate());
        // 継続中フラグが正しい値である。
        assertTrue(period.isActive());
        // notification.addError()が一度も呼ばれていない。
        verify(notification, never()).addError(anyString(), anyString());
    }

    @Test
    @DisplayName("開始年月を終了年月より大きい値でインスタンス化する")
    void test3() {
        Period period = Period.create(notification, YearMonth.of(2025, 03), YearMonth.of(2025, 02), false);
        // インスタンスがnullでない。
        assertNotNull(period);
        // isInvalidDateRange()に対応するエラーメッセージが登録される。
        verify(notification, times(
                1)).addError(
                        eq("endDate"),
                        eq("終了年月は開始年月より後の日付を指定してください。"));
        // isInvalidEndDateForIsActive()に対応するエラーメッセージが登録されない。
        verify(notification, never()).addError("endDate", "在籍中や担当中の場合は終了年月を指定しないでください。");
    }

    @Test
    @DisplayName("継続中であれば開始年月を終了年月より大きい値でインスタンス化してもisInvalidDateRange()はスルーされる")
    void test4() {
        Period period = Period.create(notification, YearMonth.of(2025, 03), YearMonth.of(2025, 02), true);
        // インスタンスがnullでない。
        assertNotNull(period);
        // isInvalidDateRange()に対応するエラーメッセージが登録されない。
        verify(notification, never()).addError("endDate", "終了年月は開始年月より後の日付を指定してください。");
        // isInvalidEndDateForIsActive()に対応するエラーメッセージが登録される。
        verify(notification, times(1)).addError(
                eq("endDate"),
                eq("在籍中や担当中の場合は終了年月を指定しないでください。"));
    }

    @Test
    @DisplayName("継続中かつ終了年月を非nullの値でインスタンス化する")
    void test5() {
        Period period = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), true);
        // インスタンスがnullでない。
        assertNotNull(period);
        // isInvalidEndDateForIsActive()に対応するエラーメッセージが登録される。
        verify(notification, times(
                1)).addError(
                        eq("endDate"),
                        eq("在籍中や担当中の場合は終了年月を指定しないでください。"));
        // isInvalidDateRange()に対応するエラーメッセージが登録されない。
        verify(notification, never()).addError("endDate", "終了年月は開始年月より後の日付を指定してください。");
    }
}
