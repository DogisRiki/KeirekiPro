package com.example.keirekipro.unit.domain.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.YearMonth;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class CareerTest {

    @Mock
    private Notification notification;

    @Test
    @DisplayName("新規構築用コンストラクタでインスタンス化する")
    void test1() {
        Period period = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), false);
        Career career = Career.create(0, "株式会社ABC", period);

        assertThat(career).isNotNull();
        assertThat(career.getId()).isNotNull();
        assertThat(career.getOrderNo()).isEqualTo(0);
        assertThat(career.getCompanyName()).isEqualTo("株式会社ABC");
        assertThat(career.getPeriod()).isEqualTo(period);
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        Period period = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), false);
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Career career = Career.reconstruct(id, 0, "株式会社ABC", period);

        assertThat(career).isNotNull();
        assertThat(career.getId()).isEqualTo(id);
        assertThat(career.getOrderNo()).isEqualTo(0);
        assertThat(career.getCompanyName()).isEqualTo("株式会社ABC");
        assertThat(career.getPeriod()).isEqualTo(period);
    }

    @Test
    @DisplayName("会社名を変更する")
    void test3() {
        Period period = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), false);
        Career beforeCareer = Career.create(0, "株式会社ABC", period);
        Career afterCareer = beforeCareer.changeCompanyName("株式会社ZZZ");

        assertThat(afterCareer.getCompanyName()).isEqualTo("株式会社ZZZ");
    }

    @Test
    @DisplayName("期間を変更する")
    void test4() {
        Period beforePeriod = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), false);
        Career beforeCareer = Career.create(0, "株式会社ABC", beforePeriod);
        Period afterPeriod = Period.create(notification, YearMonth.of(2030, 01), null, true);
        Career afterCareer = beforeCareer.changePeriod(afterPeriod);

        assertThat(afterCareer.getPeriod()).isEqualTo(afterPeriod);
    }

    @Test
    @DisplayName("会社名、期間を変更する")
    void test5() {
        Period beforePeriod = Period.create(notification, YearMonth.of(2025, 01), YearMonth.of(2025, 02), false);
        Career beforeCareer = Career.create(0, "株式会社ABC", beforePeriod);
        Period afterPeriod = Period.create(notification, YearMonth.of(2030, 01), null, true);
        Career afterCareer = beforeCareer.changePeriod(afterPeriod).changeCompanyName("株式会社ZZZ");

        assertThat(afterCareer.getPeriod()).isEqualTo(afterPeriod);
        assertThat(afterCareer.getCompanyName()).isEqualTo("株式会社ZZZ");
    }
}
