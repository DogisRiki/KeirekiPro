package com.example.keirekipro.unit.domain.service.resume;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.model.resume.TechStack;
import com.example.keirekipro.domain.service.resume.ResumeExportRuleCheckService;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.shared.ErrorCollector;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class ResumeExportRuleCheckServiceTest {

    private final ResumeExportRuleCheckService service = new ResumeExportRuleCheckService();

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final UUID RESUME_ID = UUID.fromString("223e4567-e89b-12d3-a456-426614174000");

    private static final LocalDate DATE = LocalDate.of(2024, 6, 1);
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2024, 6, 1, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2024, 6, 1, 12, 0);

    private static final String RESUME_NAME = "職務経歴書名";
    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";

    @Test
    @DisplayName("エクスポート前提条件を満たす場合、DomainExceptionをスローしない")
    void test1() {
        Resume resume = buildResume(
                ResumeName.create(new ErrorCollector(), RESUME_NAME),
                DATE,
                FullName.create(new ErrorCollector(), LAST_NAME, FIRST_NAME),
                List.of(buildCareer()),
                List.of(buildProject()),
                List.of(buildSelfPromotion()));

        assertThatCode(() -> service.execute(resume)).doesNotThrowAnyException();
    }

    @Test
    @DisplayName("必須条件が不足している場合、箇条書きメッセージでDomainExceptionをスローする")
    void test2() {
        Resume resume = buildResume(
                null,
                null,
                null,
                List.of(),
                List.of(),
                List.of());

        assertThatThrownBy(() -> service.execute(resume))
                .isInstanceOf(DomainException.class)
                .hasMessage(String.join("\n",
                        "職務経歴書をエクスポートできません。",
                        "- 職務経歴書名を入力してください。",
                        "- 日付を設定してください。",
                        "- 氏名（姓・名）を入力してください。",
                        "- 職歴を1件以上登録してください。",
                        "- プロジェクトを1件以上登録してください。",
                        "- 自己PRを1件以上登録してください。"));
    }

    @Test
    @DisplayName("氏名の姓のみ不足している場合、姓のエラーメッセージを含めてDomainExceptionをスローする")
    void test3() {
        FullName fullName = FullName.create(new ErrorCollector(), "", FIRST_NAME);

        Resume resume = buildResume(
                ResumeName.create(new ErrorCollector(), RESUME_NAME),
                DATE,
                fullName,
                List.of(buildCareer()),
                List.of(buildProject()),
                List.of(buildSelfPromotion()));

        assertThatThrownBy(() -> service.execute(resume))
                .isInstanceOf(DomainException.class)
                .hasMessage(String.join("\n",
                        "職務経歴書をエクスポートできません。",
                        "- 姓を入力してください。"));
    }

    private static Resume buildResume(
            ResumeName resumeName,
            LocalDate date,
            FullName fullName,
            List<Career> careers,
            List<Project> projects,
            List<SelfPromotion> selfPromotions) {
        return Resume.reconstruct(
                RESUME_ID,
                USER_ID,
                resumeName,
                date,
                fullName,
                CREATED_AT,
                UPDATED_AT,
                careers,
                projects,
                List.of(),
                List.of(),
                List.of(),
                selfPromotions);
    }

    private static Career buildCareer() {
        ErrorCollector errorCollector = new ErrorCollector();

        CompanyName companyName = CompanyName.create(errorCollector, "株式会社サンプル");
        Period period = Period.create(errorCollector, YearMonth.of(2023, 1), YearMonth.of(2023, 12), false);

        return Career.create(errorCollector, companyName, period);
    }

    private static Project buildProject() {
        ErrorCollector errorCollector = new ErrorCollector();

        CompanyName companyName = CompanyName.create(errorCollector, "株式会社サンプル");
        Period period = Period.create(errorCollector, YearMonth.of(2024, 1), YearMonth.of(2024, 3), false);

        Project.Process process = Project.Process.create(true, false, false, false, false, false, false);

        TechStack techStack = TechStack.create(
                TechStack.Frontend.create(List.of(), List.of(), List.of(), List.of(), List.of(), List.of(), List.of(),
                        List.of()),
                TechStack.Backend.create(List.of(), List.of(), List.of(), List.of(), List.of(), List.of(), List.of(),
                        List.of(), List.of(), List.of()),
                TechStack.Infrastructure.create(List.of(), List.of(), List.of(), List.of(), List.of(), List.of(),
                        List.of(), List.of(), List.of()),
                TechStack.Tools.create(List.of(), List.of(), List.of(), List.of(), List.of(), List.of(), List.of(),
                        List.of()));

        return Project.create(
                errorCollector,
                companyName,
                period,
                "プロジェクト名",
                "プロジェクト概要",
                "チーム構成",
                "役割",
                "成果",
                process,
                techStack);
    }

    private static SelfPromotion buildSelfPromotion() {
        ErrorCollector errorCollector = new ErrorCollector();
        return SelfPromotion.create(errorCollector, "自己PRタイトル", "自己PR内容");
    }
}
