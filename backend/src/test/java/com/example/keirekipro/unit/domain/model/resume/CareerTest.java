package com.example.keirekipro.unit.domain.model.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.YearMonth;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.shared.Notification;

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
        Period period = Period.create(notification, YearMonth.of(2025, 1), YearMonth.of(2025, 2), false);
        CompanyName companyName = CompanyName.create(notification, "株式会社ABC");
        Career career = Career.create(notification, companyName, period);

        assertThat(career).isNotNull();
        assertThat(career.getId()).isNotNull();
        assertThat(career.getCompanyName().getValue()).isEqualTo("株式会社ABC");
        assertThat(career.getPeriod()).isEqualTo(period);
    }

    @Test
    @DisplayName("再構築用コンストラクタでインスタンス化する")
    void test2() {
        Period period = Period.create(notification, YearMonth.of(2025, 1), YearMonth.of(2025, 2), false);
        CompanyName companyName = CompanyName.create(notification, "株式会社ABC");
        UUID id = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        Career career = Career.reconstruct(id, companyName, period);

        assertThat(career).isNotNull();
        assertThat(career.getId()).isEqualTo(id);
        assertThat(career.getCompanyName().getValue()).isEqualTo("株式会社ABC");
        assertThat(career.getPeriod()).isEqualTo(period);
    }

    @Test
    @DisplayName("会社名を変更する")
    void test3() {
        Period period = Period.create(notification, YearMonth.of(2025, 1), YearMonth.of(2025, 2), false);
        CompanyName beforeCompanyName = CompanyName.create(notification, "株式会社ABC");
        Career beforeCareer = Career.create(notification, beforeCompanyName, period);

        CompanyName afterCompanyName = CompanyName.create(notification, "株式会社ZZZ");
        Career afterCareer = beforeCareer.changeCompanyName(notification, afterCompanyName);

        assertThat(afterCareer.getCompanyName()).isEqualTo(afterCompanyName);
    }

    @Test
    @DisplayName("期間を変更する")
    void test4() {
        Period beforePeriod = Period.create(notification, YearMonth.of(2025, 1), YearMonth.of(2025, 2), false);
        CompanyName companyName = CompanyName.create(notification, "株式会社ABC");
        Career beforeCareer = Career.create(notification, companyName, beforePeriod);

        Period afterPeriod = Period.create(notification, YearMonth.of(2030, 1), null, true);
        Career afterCareer = beforeCareer.changePeriod(notification, afterPeriod);

        assertThat(afterCareer.getPeriod()).isEqualTo(afterPeriod);
    }

    @Test
    @DisplayName("会社名、期間を変更する")
    void test5() {
        Period beforePeriod = Period.create(notification, YearMonth.of(2025, 1), YearMonth.of(2025, 2), false);
        CompanyName beforeCompanyName = CompanyName.create(notification, "株式会社ABC");
        Career beforeCareer = Career.create(notification, beforeCompanyName, beforePeriod);

        Period afterPeriod = Period.create(notification, YearMonth.of(2030, 1), null, true);
        CompanyName afterCompanyName = CompanyName.create(notification, "株式会社ZZZ");
        Career afterCareer = beforeCareer.changePeriod(notification, afterPeriod)
                .changeCompanyName(notification, afterCompanyName);

        assertThat(afterCareer.getPeriod()).isEqualTo(afterPeriod);
        assertThat(afterCareer.getCompanyName()).isEqualTo(afterCompanyName);
    }

    @Test
    @DisplayName("会社名がnullの場合、エラーが通知される")
    void test6() {
        Notification notification = new Notification();
        Period period = Period.create(notification, YearMonth.of(2025, 1), YearMonth.of(2025, 2), false);

        Career.create(notification, null, period);

        assertThat(notification.getErrors().get("companyName")).containsExactly("会社名は入力必須です。");
    }

    @Test
    @DisplayName("期間がnullの場合、エラーが通知される")
    void test7() {
        Notification notification = new Notification();
        CompanyName companyName = CompanyName.create(notification, "株式会社ABC");

        Career.create(notification, companyName, null);

        assertThat(notification.getErrors().get("period")).containsExactly("期間は入力必須です。");
    }
}
