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

        Project.Process process = mock(Project.Process.class);
        when(process.isRequirements()).thenReturn(true);
        when(process.isBasicDesign()).thenReturn(true);
        when(process.isDetailedDesign()).thenReturn(false);
        when(process.isImplementation()).thenReturn(true);
        when(process.isIntegrationTest()).thenReturn(false);
        when(process.isSystemTest()).thenReturn(false);
        when(process.isMaintenance()).thenReturn(true);
        when(project.getProcess()).thenReturn(process);

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
        assertThat(companySections.get(0).get("companyPeriodLabel")).isEqualTo("2020年4月 〜 2022年3月");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> projects = (List<Map<String, Object>>) companySections.get(0).get("projects");
        assertThat(projects).hasSize(1);
        assertThat(projects.get(0).get("periodStartLabel")).isEqualTo("2023年1月");
        assertThat(projects.get(0).get("periodEndLabel")).isEqualTo("現在");
        assertThat(projects.get(0).get("projectLabel")).isEqualTo("新規開発プロジェクト（2023年1月 〜 現在）");
        assertThat(projects.get(0).get("projectName")).isEqualTo("新規開発プロジェクト");
        assertThat(projects.get(0).get("overview")).isEqualTo("概要です。");
        assertThat(projects.get(0).get("teamComp")).isEqualTo("5名");
        assertThat(projects.get(0).get("role")).isEqualTo("バックエンド");

        @SuppressWarnings("unchecked")
        List<String> achievements = (List<String>) projects.get(0).get("achievements");
        assertThat(achievements).containsExactly("・成果1", "・成果2", "・成果3", "成果4");

        @SuppressWarnings("unchecked")
        Map<String, Object> processModel = (Map<String, Object>) projects.get(0).get("process");
        assertThat(processModel.get("requirements")).isEqualTo(true);
        assertThat(processModel.get("basicDesign")).isEqualTo(true);
        assertThat(processModel.get("detailedDesign")).isEqualTo(false);
        assertThat(processModel.get("implementation")).isEqualTo(true);
        assertThat(processModel.get("integrationTest")).isEqualTo(false);
        assertThat(processModel.get("systemTest")).isEqualTo(false);
        assertThat(processModel.get("maintenance")).isEqualTo(true);
        assertThat(processModel.get("label")).isEqualTo("要件定義、基本設計、実装・単体テスト、運用・保守");

        @SuppressWarnings("unchecked")
        Map<String, Object> tech = (Map<String, Object>) projects.get(0).get("tech");
        assertThat(tech).isNotNull();

        @SuppressWarnings("unchecked")
        Map<String, Object> frontend = (Map<String, Object>) tech.get("frontend");
        assertThat(frontend).isNotNull();
        assertThat(frontend.get("languages")).isEqualTo(List.of("TypeScript"));
        assertThat(frontend.get("frameworks")).isEqualTo(List.of("React"));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> techSections = (List<Map<String, Object>>) projects.get(0).get("techSections");
        assertThat(techSections).hasSize(1);
        assertThat(techSections.get(0).get("title")).isEqualTo("フロントエンド");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> techLines = (List<Map<String, Object>>) techSections.get(0).get("lines");
        assertThat(techLines).hasSize(2);
        assertThat(techLines.get(0).get("label")).isEqualTo("開発言語");
        assertThat(techLines.get(0).get("value")).isEqualTo("TypeScript");
        assertThat(techLines.get(1).get("label")).isEqualTo("フレームワーク");
        assertThat(techLines.get(1).get("value")).isEqualTo("React");

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

    @Test
    @DisplayName("同一勤務先のプロジェクトは1つの会社セクションにまとめられ、異なる勤務先は別セクションになる")
    void test2() {
        // Resume
        Resume resume = mock(Resume.class);
        when(resume.getDate()).thenReturn(null);
        when(resume.getFullName()).thenReturn(null);

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
        Project project1 = mock(Project.class);
        CompanyName projectCompany1 = mock(CompanyName.class);
        when(projectCompany1.getValue()).thenReturn("株式会社ABC");
        when(project1.getCompanyName()).thenReturn(projectCompany1);
        when(project1.getName()).thenReturn("ABCプロジェクト1");

        Project project2 = mock(Project.class);
        CompanyName projectCompany2 = mock(CompanyName.class);
        when(projectCompany2.getValue()).thenReturn("株式会社ABC");
        when(project2.getCompanyName()).thenReturn(projectCompany2);
        when(project2.getName()).thenReturn("ABCプロジェクト2");

        Project project3 = mock(Project.class);
        CompanyName projectCompany3 = mock(CompanyName.class);
        when(projectCompany3.getValue()).thenReturn("株式会社DEF");
        when(project3.getCompanyName()).thenReturn(projectCompany3);
        when(project3.getName()).thenReturn("DEFプロジェクト1");

        when(resume.getProjects()).thenReturn(List.of(project1, project2, project3));

        // Certifications
        when(resume.getCertifications()).thenReturn(List.of());

        // Portfolios
        when(resume.getPortfolios()).thenReturn(List.of());

        // SNS
        when(resume.getSnsPlatforms()).thenReturn(List.of());

        // Self promotions
        when(resume.getSelfPromotions()).thenReturn(List.of());

        // 実行
        Map<String, Object> export = builder.build(resume);

        // 検証（companySections）
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> companySections = (List<Map<String, Object>>) export.get("companySections");
        assertThat(companySections).hasSize(2);

        assertThat(companySections.get(0).get("companyLabel")).isEqualTo("株式会社ABC");
        assertThat(companySections.get(0).get("companyPeriodLabel")).isEqualTo("2020年4月 〜 2022年3月");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> abcProjects = (List<Map<String, Object>>) companySections.get(0).get("projects");
        assertThat(abcProjects).hasSize(2);
        assertThat(abcProjects.get(0).get("projectName")).isEqualTo("ABCプロジェクト1");
        assertThat(abcProjects.get(1).get("projectName")).isEqualTo("ABCプロジェクト2");

        assertThat(companySections.get(1).get("companyLabel")).isEqualTo("株式会社DEF");
        assertThat(companySections.get(1).get("companyPeriodLabel")).isEqualTo("2022年4月 〜 現在");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> defProjects = (List<Map<String, Object>>) companySections.get(1).get("projects");
        assertThat(defProjects).hasSize(1);
        assertThat(defProjects.get(0).get("projectName")).isEqualTo("DEFプロジェクト1");
    }

    @Test
    @DisplayName("プロジェクトの工程・期間・技術スタックが未設定の場合はテンプレート参照可能な空モデルが構築される")
    void test3() {
        // Resume
        Resume resume = mock(Resume.class);
        when(resume.getDate()).thenReturn(null);
        when(resume.getFullName()).thenReturn(null);
        when(resume.getCareers()).thenReturn(List.of());

        // Projects
        Project project = mock(Project.class);
        when(project.getName()).thenReturn(null);
        when(project.getPeriod()).thenReturn(null);
        when(project.getProcess()).thenReturn(null);
        when(project.getTechStack()).thenReturn(null);

        when(resume.getProjects()).thenReturn(List.of(project));

        // Certifications
        when(resume.getCertifications()).thenReturn(List.of());

        // Portfolios
        when(resume.getPortfolios()).thenReturn(List.of());

        // SNS
        when(resume.getSnsPlatforms()).thenReturn(List.of());

        // Self promotions
        when(resume.getSelfPromotions()).thenReturn(List.of());

        // 実行
        Map<String, Object> export = builder.build(resume);

        // 検証（ヘッダ）
        assertThat(export.get("asOfDateLabel")).isEqualTo("");
        assertThat(export.get("fullName")).isEqualTo("");

        // 検証（companySections / projects）
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> companySections = (List<Map<String, Object>>) export.get("companySections");
        assertThat(companySections).hasSize(1);
        assertThat(companySections.get(0).get("companyLabel")).isEqualTo("");
        assertThat(companySections.get(0).get("companyPeriodLabel")).isEqualTo("");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> projects = (List<Map<String, Object>>) companySections.get(0).get("projects");
        assertThat(projects).hasSize(1);
        assertThat(projects.get(0).get("periodStartLabel")).isEqualTo("");
        assertThat(projects.get(0).get("periodEndLabel")).isEqualTo("");
        assertThat(projects.get(0).get("projectLabel")).isEqualTo("（）");
        assertThat(projects.get(0).get("projectName")).isEqualTo("");
        assertThat(projects.get(0).get("achievements")).isEqualTo(List.of());
        assertThat(projects.get(0).get("tech")).isNull();
        assertThat(projects.get(0).get("techSections")).isEqualTo(List.of());

        @SuppressWarnings("unchecked")
        Map<String, Object> processModel = (Map<String, Object>) projects.get(0).get("process");
        assertThat(processModel.get("requirements")).isEqualTo(false);
        assertThat(processModel.get("basicDesign")).isEqualTo(false);
        assertThat(processModel.get("detailedDesign")).isEqualTo(false);
        assertThat(processModel.get("implementation")).isEqualTo(false);
        assertThat(processModel.get("integrationTest")).isEqualTo(false);
        assertThat(processModel.get("systemTest")).isEqualTo(false);
        assertThat(processModel.get("maintenance")).isEqualTo(false);
        assertThat(processModel.get("label")).isEqualTo("");
    }

    @Test
    @DisplayName("終了年月があるプロジェクトは開始年月と終了年月が分割されて構築される")
    void test4() {
        // Resume
        Resume resume = mock(Resume.class);
        when(resume.getDate()).thenReturn(null);
        when(resume.getFullName()).thenReturn(null);
        when(resume.getCareers()).thenReturn(List.of());

        // Projects
        Project project = mock(Project.class);
        Period projectPeriod = mock(Period.class);
        when(projectPeriod.getStartDate()).thenReturn(YearMonth.of(2023, 1));
        when(projectPeriod.getEndDate()).thenReturn(YearMonth.of(2023, 12));
        when(projectPeriod.isActive()).thenReturn(false);
        when(project.getPeriod()).thenReturn(projectPeriod);
        when(project.getName()).thenReturn("保守開発プロジェクト");

        when(resume.getProjects()).thenReturn(List.of(project));

        // Certifications
        when(resume.getCertifications()).thenReturn(List.of());

        // Portfolios
        when(resume.getPortfolios()).thenReturn(List.of());

        // SNS
        when(resume.getSnsPlatforms()).thenReturn(List.of());

        // Self promotions
        when(resume.getSelfPromotions()).thenReturn(List.of());

        // 実行
        Map<String, Object> export = builder.build(resume);

        // 検証（companySections / projects）
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> companySections = (List<Map<String, Object>>) export.get("companySections");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> projects = (List<Map<String, Object>>) companySections.get(0).get("projects");
        assertThat(projects).hasSize(1);
        assertThat(projects.get(0).get("periodStartLabel")).isEqualTo("2023年1月");
        assertThat(projects.get(0).get("periodEndLabel")).isEqualTo("2023年12月");
        assertThat(projects.get(0).get("projectLabel")).isEqualTo("保守開発プロジェクト（2023年1月 〜 2023年12月）");
    }

    @Test
    @DisplayName("技術スタックは帳票表示用のセクションと行に変換される")
    void test5() {
        // Resume
        Resume resume = mock(Resume.class);
        when(resume.getDate()).thenReturn(null);
        when(resume.getFullName()).thenReturn(null);
        when(resume.getCareers()).thenReturn(List.of());

        // Projects
        Project project = mock(Project.class);
        when(project.getName()).thenReturn("技術スタック確認プロジェクト");

        TechStack.Frontend fe = TechStack.Frontend.create(
                List.of(" TypeScript ", "TypeScript", ""),
                List.of("React"),
                List.of("React Hook Form"),
                List.of("Vite"),
                List.of("npm"),
                List.of("ESLint"),
                List.of("Prettier"),
                List.of("Vitest"));

        TechStack.Backend be = TechStack.Backend.create(
                List.of(" Java ", "Java"),
                List.of("Spring Boot"),
                List.of("Lombok"),
                List.of("Gradle"),
                List.of("Gradle"),
                List.of("Checkstyle"),
                List.of("Spotless"),
                List.of("JUnit"),
                List.of("MyBatis"),
                List.of("Spring Security"));

        TechStack.Infrastructure infra = TechStack.Infrastructure.create(
                List.of("AWS"),
                List.of("Linux"),
                List.of("Docker"),
                List.of("PostgreSQL"),
                List.of("Nginx"),
                List.of("GitHub Actions"),
                List.of("Terraform"),
                List.of("CloudWatch"),
                List.of("CloudWatch Logs"));

        TechStack.Tools tools = TechStack.Tools.create(
                List.of("GitHub"),
                List.of("Jira"),
                List.of("Slack"),
                List.of("Confluence"),
                List.of("Postman"),
                List.of("Figma"),
                List.of("IntelliJ IDEA"),
                List.of("Docker Desktop"));

        TechStack techStack = TechStack.create(fe, be, infra, tools);
        when(project.getTechStack()).thenReturn(techStack);

        when(resume.getProjects()).thenReturn(List.of(project));

        // Certifications
        when(resume.getCertifications()).thenReturn(List.of());

        // Portfolios
        when(resume.getPortfolios()).thenReturn(List.of());

        // SNS
        when(resume.getSnsPlatforms()).thenReturn(List.of());

        // Self promotions
        when(resume.getSelfPromotions()).thenReturn(List.of());

        // 実行
        Map<String, Object> export = builder.build(resume);

        // 検証（companySections / projects）
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> companySections = (List<Map<String, Object>>) export.get("companySections");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> projects = (List<Map<String, Object>>) companySections.get(0).get("projects");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> techSections = (List<Map<String, Object>>) projects.get(0).get("techSections");
        assertThat(techSections).hasSize(4);

        // 検証（フロントエンド）
        assertThat(techSections.get(0).get("title")).isEqualTo("フロントエンド");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> frontendLines = (List<Map<String, Object>>) techSections.get(0).get("lines");
        assertThat(frontendLines).hasSize(8);
        assertThat(frontendLines.get(0).get("label")).isEqualTo("開発言語");
        assertThat(frontendLines.get(0).get("value")).isEqualTo("TypeScript");
        assertThat(frontendLines.get(1).get("label")).isEqualTo("フレームワーク");
        assertThat(frontendLines.get(1).get("value")).isEqualTo("React");
        assertThat(frontendLines.get(2).get("label")).isEqualTo("ライブラリ");
        assertThat(frontendLines.get(2).get("value")).isEqualTo("React Hook Form");
        assertThat(frontendLines.get(3).get("label")).isEqualTo("ビルドツール");
        assertThat(frontendLines.get(3).get("value")).isEqualTo("Vite");
        assertThat(frontendLines.get(4).get("label")).isEqualTo("パッケージマネージャー");
        assertThat(frontendLines.get(4).get("value")).isEqualTo("npm");
        assertThat(frontendLines.get(5).get("label")).isEqualTo("リンター");
        assertThat(frontendLines.get(5).get("value")).isEqualTo("ESLint");
        assertThat(frontendLines.get(6).get("label")).isEqualTo("フォーマッター");
        assertThat(frontendLines.get(6).get("value")).isEqualTo("Prettier");
        assertThat(frontendLines.get(7).get("label")).isEqualTo("テストツール");
        assertThat(frontendLines.get(7).get("value")).isEqualTo("Vitest");

        // 検証（バックエンド）
        assertThat(techSections.get(1).get("title")).isEqualTo("バックエンド");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> backendLines = (List<Map<String, Object>>) techSections.get(1).get("lines");
        assertThat(backendLines).hasSize(10);
        assertThat(backendLines.get(0).get("label")).isEqualTo("開発言語");
        assertThat(backendLines.get(0).get("value")).isEqualTo("Java");
        assertThat(backendLines.get(1).get("label")).isEqualTo("フレームワーク");
        assertThat(backendLines.get(1).get("value")).isEqualTo("Spring Boot");
        assertThat(backendLines.get(2).get("label")).isEqualTo("ライブラリ");
        assertThat(backendLines.get(2).get("value")).isEqualTo("Lombok");
        assertThat(backendLines.get(3).get("label")).isEqualTo("ビルドツール");
        assertThat(backendLines.get(3).get("value")).isEqualTo("Gradle");
        assertThat(backendLines.get(4).get("label")).isEqualTo("パッケージマネージャー");
        assertThat(backendLines.get(4).get("value")).isEqualTo("Gradle");
        assertThat(backendLines.get(5).get("label")).isEqualTo("リンター");
        assertThat(backendLines.get(5).get("value")).isEqualTo("Checkstyle");
        assertThat(backendLines.get(6).get("label")).isEqualTo("フォーマッター");
        assertThat(backendLines.get(6).get("value")).isEqualTo("Spotless");
        assertThat(backendLines.get(7).get("label")).isEqualTo("テストツール");
        assertThat(backendLines.get(7).get("value")).isEqualTo("JUnit");
        assertThat(backendLines.get(8).get("label")).isEqualTo("ORM");
        assertThat(backendLines.get(8).get("value")).isEqualTo("MyBatis");
        assertThat(backendLines.get(9).get("label")).isEqualTo("認証");
        assertThat(backendLines.get(9).get("value")).isEqualTo("Spring Security");

        // 検証（インフラ）
        assertThat(techSections.get(2).get("title")).isEqualTo("インフラ");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> infrastructureLines = (List<Map<String, Object>>) techSections.get(2).get("lines");
        assertThat(infrastructureLines).hasSize(9);
        assertThat(infrastructureLines.get(0).get("label")).isEqualTo("クラウド");
        assertThat(infrastructureLines.get(0).get("value")).isEqualTo("AWS");
        assertThat(infrastructureLines.get(1).get("label")).isEqualTo("OS");
        assertThat(infrastructureLines.get(1).get("value")).isEqualTo("Linux");
        assertThat(infrastructureLines.get(2).get("label")).isEqualTo("コンテナ");
        assertThat(infrastructureLines.get(2).get("value")).isEqualTo("Docker");
        assertThat(infrastructureLines.get(3).get("label")).isEqualTo("データベース");
        assertThat(infrastructureLines.get(3).get("value")).isEqualTo("PostgreSQL");
        assertThat(infrastructureLines.get(4).get("label")).isEqualTo("Webサーバー");
        assertThat(infrastructureLines.get(4).get("value")).isEqualTo("Nginx");
        assertThat(infrastructureLines.get(5).get("label")).isEqualTo("CI/CD");
        assertThat(infrastructureLines.get(5).get("value")).isEqualTo("GitHub Actions");
        assertThat(infrastructureLines.get(6).get("label")).isEqualTo("IaC");
        assertThat(infrastructureLines.get(6).get("value")).isEqualTo("Terraform");
        assertThat(infrastructureLines.get(7).get("label")).isEqualTo("監視");
        assertThat(infrastructureLines.get(7).get("value")).isEqualTo("CloudWatch");
        assertThat(infrastructureLines.get(8).get("label")).isEqualTo("ロギング");
        assertThat(infrastructureLines.get(8).get("value")).isEqualTo("CloudWatch Logs");

        // 検証（開発支援ツール）
        assertThat(techSections.get(3).get("title")).isEqualTo("開発支援ツール");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> toolLines = (List<Map<String, Object>>) techSections.get(3).get("lines");
        assertThat(toolLines).hasSize(8);
        assertThat(toolLines.get(0).get("label")).isEqualTo("ソース管理");
        assertThat(toolLines.get(0).get("value")).isEqualTo("GitHub");
        assertThat(toolLines.get(1).get("label")).isEqualTo("プロジェクト管理");
        assertThat(toolLines.get(1).get("value")).isEqualTo("Jira");
        assertThat(toolLines.get(2).get("label")).isEqualTo("コミュニケーション");
        assertThat(toolLines.get(2).get("value")).isEqualTo("Slack");
        assertThat(toolLines.get(3).get("label")).isEqualTo("ドキュメント");
        assertThat(toolLines.get(3).get("value")).isEqualTo("Confluence");
        assertThat(toolLines.get(4).get("label")).isEqualTo("API開発");
        assertThat(toolLines.get(4).get("value")).isEqualTo("Postman");
        assertThat(toolLines.get(5).get("label")).isEqualTo("デザイン");
        assertThat(toolLines.get(5).get("value")).isEqualTo("Figma");
        assertThat(toolLines.get(6).get("label")).isEqualTo("エディタ");
        assertThat(toolLines.get(6).get("value")).isEqualTo("IntelliJ IDEA");
        assertThat(toolLines.get(7).get("label")).isEqualTo("開発環境");
        assertThat(toolLines.get(7).get("value")).isEqualTo("Docker Desktop");
    }

    @Test
    @DisplayName("会社名に一致する職歴がない場合は勤務期間ラベルが空文字になる")
    void test6() {
        // Resume
        Resume resume = mock(Resume.class);
        when(resume.getDate()).thenReturn(null);
        when(resume.getFullName()).thenReturn(null);

        // Careers
        Career career = mock(Career.class);
        CompanyName companyName = mock(CompanyName.class);
        when(companyName.getValue()).thenReturn("株式会社ABC");
        when(career.getCompanyName()).thenReturn(companyName);
        when(resume.getCareers()).thenReturn(List.of(career));

        // Projects
        Project project = mock(Project.class);
        CompanyName projectCompany = mock(CompanyName.class);
        when(projectCompany.getValue()).thenReturn("株式会社XYZ");
        when(project.getCompanyName()).thenReturn(projectCompany);
        when(project.getName()).thenReturn("一致しない会社のプロジェクト");

        when(resume.getProjects()).thenReturn(List.of(project));

        // Certifications
        when(resume.getCertifications()).thenReturn(List.of());

        // Portfolios
        when(resume.getPortfolios()).thenReturn(List.of());

        // SNS
        when(resume.getSnsPlatforms()).thenReturn(List.of());

        // Self promotions
        when(resume.getSelfPromotions()).thenReturn(List.of());

        // 実行
        Map<String, Object> export = builder.build(resume);

        // 検証（companySections）
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> companySections = (List<Map<String, Object>>) export.get("companySections");
        assertThat(companySections).hasSize(1);
        assertThat(companySections.get(0).get("companyLabel")).isEqualTo("株式会社XYZ");
        assertThat(companySections.get(0).get("companyPeriodLabel")).isEqualTo("");
    }
}
