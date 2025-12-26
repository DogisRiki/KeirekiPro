package com.example.keirekipro.unit.infrastructure.export.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.Map;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.model.resume.SnsPlatform;
import com.example.keirekipro.domain.model.resume.TechStack;
import com.example.keirekipro.infrastructure.export.resume.ResumeExportModelBuilder;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ResumeExportModelBuilderTest {

    private final ResumeExportModelBuilder builder = new ResumeExportModelBuilder();

    @Test
    @DisplayName("buildメソッドでテンプレート向けのexportモデルが構築され、整形処理が適用される")
    void test1() {
        // Resume
        Resume resume = mock(Resume.class);
        when(resume.getDate()).thenReturn(LocalDate.of(2025, 1, 2));

        FullName fullName = mock(FullName.class);
        when(fullName.getLastName()).thenReturn("山田");
        when(fullName.getFirstName()).thenReturn("太郎");
        when(resume.getFullName()).thenReturn(fullName);

        // Careers
        Career career1 = mock(Career.class);
        Period careerPeriod1 = mock(Period.class);
        when(careerPeriod1.getStartDate()).thenReturn(YearMonth.of(2020, 4));
        when(careerPeriod1.getEndDate()).thenReturn(YearMonth.of(2022, 3));
        when(careerPeriod1.isActive()).thenReturn(false);
        when(career1.getPeriod()).thenReturn(careerPeriod1);

        CompanyName companyName1 = mock(CompanyName.class);
        when(companyName1.getValue()).thenReturn("株式会社ABC");
        when(career1.getCompanyName()).thenReturn(companyName1);

        Career career2 = mock(Career.class);
        Period careerPeriod2 = mock(Period.class);
        when(careerPeriod2.getStartDate()).thenReturn(YearMonth.of(2022, 4));
        when(careerPeriod2.isActive()).thenReturn(true);
        when(career2.getPeriod()).thenReturn(careerPeriod2);

        CompanyName companyName2 = mock(CompanyName.class);
        when(companyName2.getValue()).thenReturn("株式会社DEF");
        when(career2.getCompanyName()).thenReturn(companyName2);

        when(resume.getCareers()).thenReturn(List.of(career1, career2));

        // Projects
        Project project = mock(Project.class);

        CompanyName projectCompany = mock(CompanyName.class);
        when(projectCompany.getValue()).thenReturn("株式会社ABC");
        when(project.getCompanyName()).thenReturn(projectCompany);

        Period projectPeriod = mock(Period.class);
        when(projectPeriod.getStartDate()).thenReturn(YearMonth.of(2023, 1));
        when(projectPeriod.isActive()).thenReturn(true);
        when(project.getPeriod()).thenReturn(projectPeriod);

        when(project.getName()).thenReturn("新規開発プロジェクト");
        when(project.getOverview()).thenReturn("概要です。");
        when(project.getTeamComp()).thenReturn("5名");
        when(project.getRole()).thenReturn("バックエンド");
        when(project.getAchievement()).thenReturn("- 成果1\n* 成果2\n• 成果3\n成果4");
        when(project.getProcess()).thenReturn(mock(Project.Process.class));

        TechStack.Frontend fe = TechStack.Frontend.create(
                List.of(" TypeScript ", "TypeScript", ""),
                List.of("React"),
                null,
                null,
                null,
                null,
                null,
                null);
        TechStack techStack = TechStack.create(fe, null, null, null);
        when(project.getTechStack()).thenReturn(techStack);

        when(resume.getProjects()).thenReturn(List.of(project));

        // Certifications
        Certification cert = mock(Certification.class);
        when(cert.getDate()).thenReturn(YearMonth.of(2021, 7));
        when(cert.getName()).thenReturn("基本情報技術者");
        when(resume.getCertifications()).thenReturn(List.of(cert));

        // Portfolios
        Portfolio portfolio = mock(Portfolio.class);
        when(portfolio.getName()).thenReturn("Portfolio1");
        Link link = mock(Link.class);
        when(link.getValue()).thenReturn("https://example.com");
        when(portfolio.getLink()).thenReturn(link);
        when(portfolio.getTechStack()).thenReturn("Spring Boot / React");
        when(portfolio.getOverview()).thenReturn("概要");
        when(resume.getPortfolios()).thenReturn(List.of(portfolio));

        // SNS
        SnsPlatform sns = mock(SnsPlatform.class);
        when(sns.getName()).thenReturn("GitHub");
        Link snsLink = mock(Link.class);
        when(snsLink.getValue()).thenReturn("https://github.com/example");
        when(sns.getLink()).thenReturn(snsLink);
        when(resume.getSnsPlatforms()).thenReturn(List.of(sns));

        // Self promotions
        SelfPromotion sp = mock(SelfPromotion.class);
        when(sp.getTitle()).thenReturn("強み");
        when(sp.getContent()).thenReturn("内容");
        when(resume.getSelfPromotions()).thenReturn(List.of(sp));

        // 実行
        Map<String, Object> export = builder.build(resume);

        // 検証（ヘッダ）
        assertThat(export.get("title")).isEqualTo("職務経歴書");
        assertThat(export.get("asOfDateLabel")).isEqualTo("2025年1月2日現在");
        assertThat(export.get("fullName")).isEqualTo("山田 太郎");

        // 検証（careers）
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> careers = (List<Map<String, Object>>) export.get("careers");
        assertThat(careers).hasSize(2);
        assertThat(careers.get(0).get("periodLabel")).isEqualTo("2020年4月 〜 2022年3月");
        assertThat(careers.get(0).get("companyName")).isEqualTo("株式会社ABC");
        assertThat(careers.get(1).get("periodLabel")).isEqualTo("2022年4月 〜 現在");
        assertThat(careers.get(1).get("companyName")).isEqualTo("株式会社DEF");

        // 検証（companySections / projects）
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> companySections = (List<Map<String, Object>>) export.get("companySections");
        assertThat(companySections).hasSize(1);
        assertThat(companySections.get(0).get("companyLabel")).isEqualTo("株式会社ABC");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> projects = (List<Map<String, Object>>) companySections.get(0).get("projects");
        assertThat(projects).hasSize(1);
        assertThat(projects.get(0).get("projectLabel")).isEqualTo("新規開発プロジェクト（2023年1月 〜 現在）");

        @SuppressWarnings("unchecked")
        List<String> achievements = (List<String>) projects.get(0).get("achievements");
        assertThat(achievements).containsExactly("・成果1", "・成果2", "・成果3", "成果4");

        @SuppressWarnings("unchecked")
        Map<String, Object> tech = (Map<String, Object>) projects.get(0).get("tech");
        assertThat(tech).isNotNull();
        @SuppressWarnings("unchecked")
        Map<String, Object> frontend = (Map<String, Object>) tech.get("frontend");
        assertThat(frontend).isNotNull();
        assertThat(frontend.get("languages")).isEqualTo(List.of("TypeScript"));
        assertThat(frontend.get("frameworks")).isEqualTo(List.of("React"));

        // 検証（certifications）
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> certifications = (List<Map<String, Object>>) export.get("certifications");
        assertThat(certifications).hasSize(1);
        assertThat(certifications.get(0).get("acquiredAtLabel")).isEqualTo("2021年7月");
        assertThat(certifications.get(0).get("name")).isEqualTo("基本情報技術者");

        // 検証（portfolios）
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> portfolios = (List<Map<String, Object>>) export.get("portfolios");
        assertThat(portfolios).hasSize(1);
        assertThat(portfolios.get(0).get("name")).isEqualTo("Portfolio1");
        assertThat(portfolios.get(0).get("url")).isEqualTo("https://example.com");
        assertThat(portfolios.get(0).get("techStack")).isEqualTo("Spring Boot / React");
        assertThat(portfolios.get(0).get("overview")).isEqualTo("概要");

        // 検証（snsPlatforms）
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> snsPlatforms = (List<Map<String, Object>>) export.get("snsPlatforms");
        assertThat(snsPlatforms).hasSize(1);
        assertThat(snsPlatforms.get(0).get("name")).isEqualTo("GitHub");
        assertThat(snsPlatforms.get(0).get("url")).isEqualTo("https://github.com/example");

        // 検証（selfPromotions）
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> selfPromotions = (List<Map<String, Object>>) export.get("selfPromotions");
        assertThat(selfPromotions).hasSize(1);
        assertThat(selfPromotions.get(0).get("title")).isEqualTo("強み");
        assertThat(selfPromotions.get(0).get("content")).isEqualTo("内容");
    }
}
