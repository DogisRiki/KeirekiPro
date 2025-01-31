package com.example.keirekipro.domain.resume;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.time.YearMonth;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.shared.Notification;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class CareerTest {

    @Mock
    private Notification notification;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Period period = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), false);
        Career career = Career.create(0, "株式会社ABC", period);
        // インスタンスがnullでない。
        assertNotNull(career);
        // idが生成されている。
        assertNotNull(career.getId());
        // 並び順が正しい値である。
        assertEquals(0, career.getOrderNo());
        // 会社名が正しい値である。
        assertEquals("株式会社ABC", career.getCompanyName());
        // 期間が正しい値である。
        assertEquals(period, career.getPeriod());
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        Period period = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), false);
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Career career = Career.reconstruct(id, 0, "株式会社ABC", period);
        // インスタンスがnullでない。
        assertNotNull(career);
        // idが正しい値である。
        assertEquals(career.getId(), id);
        // 並び順が正しい値である。
        assertEquals(career.getOrderNo(), 0);
        // 会社名が正しい値である。
        assertEquals("株式会社ABC", career.getCompanyName());
        // 期間が正しい値である。
        assertEquals(period, career.getPeriod());
    }

    @Test
    @DisplayName("会社名を変更する")
    void test3() {
        Period period = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), false);
        Career beforeCareer = Career.create(0, "株式会社ABC", period);
        Career afterCareer = beforeCareer.changeCompanyName("株式会社ZZZ");
        // 変更した会社名が正しい値である。
        assertEquals("株式会社ZZZ", afterCareer.getCompanyName());
    }

    @Test
    @DisplayName("期間を変更する")
    void test4() {
        Period beforePeriod = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), false);
        Career beforeCareer = Career.create(0, "株式会社ABC", beforePeriod);
        Period afterPeriod = Period.create(notification, YearMonth.of(2030, 01), null, true);
        Career afterCareer = beforeCareer.changePeriod(afterPeriod);
        // 変更した期間が正しい値である。
        assertEquals(afterPeriod, afterCareer.getPeriod());
    }

    @Test
    @DisplayName("会社名、期間を変更する")
    void test5() {
        Period beforePeriod = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), false);
        Career beforeCareer = Career.create(0, "株式会社ABC", beforePeriod);
        Period afterPeriod = Period.create(notification, YearMonth.of(2030, 01), null, true);
        Career afterCareer = beforeCareer.changePeriod(afterPeriod).changeCompanyName("株式会社ZZZ");
        // 変更した項目が正しい値である。
        assertEquals(afterPeriod, afterCareer.getPeriod());
        assertEquals("株式会社ZZZ", afterCareer.getCompanyName());
    }
}
