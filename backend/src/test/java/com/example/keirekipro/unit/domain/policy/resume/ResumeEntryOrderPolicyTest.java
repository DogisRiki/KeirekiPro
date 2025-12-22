package com.example.keirekipro.unit.domain.policy.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.time.YearMonth;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.model.resume.SnsPlatform;
import com.example.keirekipro.domain.policy.resume.ResumeEntryOrderPolicy;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class ResumeEntryOrderPolicyTest {

    @Test
    @DisplayName("職歴: 継続中が最上位であること")
    void test1() {
        Period inactivePeriod = inactivePeriodOnlyActiveFlag();
        Career inactive = career(inactivePeriod);

        Period activePeriod = activePeriodOnlyActiveFlag();
        Career active = career(activePeriod);

        List<Career> list = new ArrayList<>(List.of(inactive, active));
        list.sort(ResumeEntryOrderPolicy.careerDesc());

        assertThat(list).containsExactly(active, inactive);
    }

    @Test
    @DisplayName("職歴: 終了日が新しいものが上であること（非継続同士）")
    void test2() {
        Career newerEnd = career(inactivePeriodWithEndOnly(YearMonth.of(2025, 1)));
        Career olderEnd = career(inactivePeriodWithEndOnly(YearMonth.of(2024, 12)));

        List<Career> list = new ArrayList<>(List.of(olderEnd, newerEnd));
        list.sort(ResumeEntryOrderPolicy.careerDesc());

        assertThat(list).containsExactly(newerEnd, olderEnd);
    }

    @Test
    @DisplayName("職歴: 終了日が同じ場合は開始日が新しいものが上であること（非継続同士）")
    void test3() {
        YearMonth sameEnd = YearMonth.of(2025, 1);

        Career newerStart = career(inactivePeriodWithEndAndStart(sameEnd, YearMonth.of(2024, 2)));
        Career olderStart = career(inactivePeriodWithEndAndStart(sameEnd, YearMonth.of(2023, 1)));

        List<Career> list = new ArrayList<>(List.of(olderStart, newerStart));
        list.sort(ResumeEntryOrderPolicy.careerDesc());

        assertThat(list).containsExactly(newerStart, olderStart);
    }

    @Test
    @DisplayName("職歴: 期間がnullのものは末尾扱いであること")
    void test4() {
        Period anyPeriod = mock(Period.class);
        Career hasPeriod = career(anyPeriod);

        Career nullPeriod = career(null);

        List<Career> list = new ArrayList<>(List.of(nullPeriod, hasPeriod));
        list.sort(ResumeEntryOrderPolicy.careerDesc());

        assertThat(list).containsExactly(hasPeriod, nullPeriod);
    }

    @Test
    @DisplayName("職歴: 期間が同一の場合はUUID昇順で安定化されること")
    void test5() {
        Period same = inactivePeriodWithEndAndStart(YearMonth.of(2024, 12), YearMonth.of(2024, 1));

        UUID idSmall = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
        UUID idLarge = UUID.fromString("123e4567-e89b-12d3-a456-426614174001");

        Career a = careerWithId(idLarge, same);
        Career b = careerWithId(idSmall, same);

        List<Career> list = new ArrayList<>(List.of(a, b));
        list.sort(ResumeEntryOrderPolicy.careerDesc());

        assertThat(list).containsExactly(b, a);
    }

    @Test
    @DisplayName("プロジェクト: 継続中が最上位であること")
    void test6() {
        Period inactivePeriod = inactivePeriodOnlyActiveFlag();
        Project inactive = project(inactivePeriod);

        Period activePeriod = activePeriodOnlyActiveFlag();
        Project active = project(activePeriod);

        List<Project> list = new ArrayList<>(List.of(inactive, active));
        list.sort(ResumeEntryOrderPolicy.projectDesc());

        assertThat(list).containsExactly(active, inactive);
    }

    @Test
    @DisplayName("資格: 取得日が新しいものが上であること")
    void test7() {
        Certification newer = certificationWithDate(YearMonth.of(2025, 6));
        Certification older = certificationWithDate(YearMonth.of(2024, 12));

        List<Certification> list = new ArrayList<>(List.of(older, newer));
        list.sort(ResumeEntryOrderPolicy.certificationDesc());

        assertThat(list).containsExactly(newer, older);
    }

    @Test
    @DisplayName("資格: 取得日がnullのものは末尾扱いであること")
    void test8() {
        Certification hasDate = certificationWithDate(YearMonth.of(2025, 6));
        Certification nullDate = certificationWithDate(null);

        List<Certification> list = new ArrayList<>(List.of(nullDate, hasDate));
        list.sort(ResumeEntryOrderPolicy.certificationDesc());

        assertThat(list).containsExactly(hasDate, nullDate);
    }

    @Test
    @DisplayName("ポートフォリオ: 名前の辞書順で昇順になること（nullは末尾）")
    void test9() {
        Portfolio a = portfolioWithName("あ");
        Portfolio i = portfolioWithName("い");
        Portfolio nullName = portfolioWithName(null);

        List<Portfolio> list = new ArrayList<>(List.of(i, nullName, a));
        list.sort(ResumeEntryOrderPolicy.portfolioNameAsc());

        assertThat(list).containsExactly(a, i, nullName);
    }

    @Test
    @DisplayName("SNSプラットフォーム: 名前が同一の場合はUUID昇順で安定化されること")
    void test10() {
        UUID idSmall = UUID.fromString("523e4567-e89b-12d3-a456-426614174000");
        UUID idLarge = UUID.fromString("523e4567-e89b-12d3-a456-426614174001");

        SnsPlatform a = snsPlatformWithNameAndId("GitHub", idLarge);
        SnsPlatform b = snsPlatformWithNameAndId("GitHub", idSmall);

        List<SnsPlatform> list = new ArrayList<>(List.of(a, b));
        list.sort(ResumeEntryOrderPolicy.snsPlatFormNameAsc());

        assertThat(list).containsExactly(b, a);
    }

    @Test
    @DisplayName("自己PR: タイトルがnullのものは末尾扱いであること")
    void test11() {
        SelfPromotion hasTitle = selfPromotionWithTitle("自己PR");
        SelfPromotion nullTitle = selfPromotionWithTitle(null);

        List<SelfPromotion> list = new ArrayList<>(List.of(nullTitle, hasTitle));
        list.sort(ResumeEntryOrderPolicy.selfPromotionTitleAsc());

        assertThat(list).containsExactly(hasTitle, nullTitle);
    }

    private static Period activePeriodOnlyActiveFlag() {
        Period period = mock(Period.class);
        when(period.isActive()).thenReturn(true);
        return period;
    }

    private static Period inactivePeriodOnlyActiveFlag() {
        Period period = mock(Period.class);
        when(period.isActive()).thenReturn(false);
        return period;
    }

    private static Period inactivePeriodWithEndOnly(YearMonth endDate) {
        Period period = mock(Period.class);
        when(period.isActive()).thenReturn(false);
        when(period.getEndDate()).thenReturn(endDate);
        return period;
    }

    private static Period inactivePeriodWithEndAndStart(YearMonth endDate, YearMonth startDate) {
        Period period = mock(Period.class);
        when(period.isActive()).thenReturn(false);
        when(period.getEndDate()).thenReturn(endDate);
        when(period.getStartDate()).thenReturn(startDate);
        return period;
    }

    private static Career career(Period period) {
        Career career = mock(Career.class);
        when(career.getPeriod()).thenReturn(period);
        return career;
    }

    private static Career careerWithId(UUID id, Period period) {
        Career career = mock(Career.class);
        when(career.getId()).thenReturn(id);
        when(career.getPeriod()).thenReturn(period);
        return career;
    }

    private static Project project(Period period) {
        Project project = mock(Project.class);
        when(project.getPeriod()).thenReturn(period);
        return project;
    }

    private static Certification certificationWithDate(YearMonth date) {
        Certification certification = mock(Certification.class);
        when(certification.getDate()).thenReturn(date);
        return certification;
    }

    private static Portfolio portfolioWithName(String name) {
        Portfolio portfolio = mock(Portfolio.class);
        when(portfolio.getName()).thenReturn(name);
        return portfolio;
    }

    private static SnsPlatform snsPlatformWithNameAndId(String name, UUID id) {
        SnsPlatform snsPlatform = mock(SnsPlatform.class);
        when(snsPlatform.getName()).thenReturn(name);
        when(snsPlatform.getId()).thenReturn(id);
        return snsPlatform;
    }

    private static SelfPromotion selfPromotionWithTitle(String title) {
        SelfPromotion selfPromotion = mock(SelfPromotion.class);
        when(selfPromotion.getTitle()).thenReturn(title);
        return selfPromotion;
    }
}
