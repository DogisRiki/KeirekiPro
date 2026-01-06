package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.usecase.query.resume.ResumeBackupQuery;
import com.example.keirekipro.usecase.query.resume.dto.ResumeBackupQueryDto;
import com.example.keirekipro.usecase.resume.BackupResumeUseCase;
import com.example.keirekipro.usecase.resume.dto.BackupResumeUseCaseDto;
import com.example.keirekipro.usecase.resume.policy.ResumeBackupVersion;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class BackupResumeUseCaseTest {

    @Mock
    private ResumeBackupQuery resumeBackupQuery;

    private BackupResumeUseCase useCase;

    @BeforeEach
    void setUp() {
        useCase = new BackupResumeUseCase(resumeBackupQuery);
    }

    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final String RESUME_NAME = "職務経歴書1";

    @Test
    @DisplayName("バックアップできる")
    void test1() {
        // モック設定
        ResumeBackupQueryDto queryDto = buildQueryDto();
        when(resumeBackupQuery.findByIdForBackup(RESUME_ID, USER_ID)).thenReturn(Optional.of(queryDto));

        // exportedAtの検証用
        Instant before = Instant.now();

        // 実行
        BackupResumeUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID);

        Instant after = Instant.now();

        // 呼び出し検証
        verify(resumeBackupQuery).findByIdForBackup(RESUME_ID, USER_ID);

        // レスポンス検証（メタ情報）
        assertThat(actual.getFileName()).isEqualTo("職務経歴書1_backup.json");
        assertThat(actual.getContentType()).isEqualTo("application/json");
        assertThat(actual.getVersion()).isEqualTo(ResumeBackupVersion.SUPPORTED_VERSION);
        assertThat(actual.getExportedAt()).isNotNull();
        assertThat(actual.getExportedAt()).isBetween(before, after);

        // Resume（親フィールド）の検証
        BackupResumeUseCaseDto.ResumeDto r = actual.getResume();
        assertThat(r.getResumeName()).isEqualTo(RESUME_NAME);
        assertThat(r.getDate()).isEqualTo(LocalDate.of(2025, 1, 1));
        assertThat(r.getLastName()).isEqualTo("山田");
        assertThat(r.getFirstName()).isEqualTo("太郎");

        // Careerの検証
        assertThat(r.getCareers()).hasSize(1);
        BackupResumeUseCaseDto.CareerDto c = r.getCareers().get(0);
        assertThat(c.getCompanyName()).isEqualTo("Company");
        assertThat(c.getStartDate()).isEqualTo(YearMonth.of(2020, 1));
        assertThat(c.getEndDate()).isNull();
        assertThat(c.isActive()).isTrue();

        // Projectの検証
        assertThat(r.getProjects()).hasSize(1);
        BackupResumeUseCaseDto.ProjectDto p = r.getProjects().get(0);
        assertThat(p.getCompanyName()).isEqualTo("Company");
        assertThat(p.getStartDate()).isEqualTo(YearMonth.of(2021, 1));
        assertThat(p.getEndDate()).isNull();
        assertThat(p.isActive()).isTrue();
        assertThat(p.getName()).isEqualTo("Project");
        assertThat(p.getOverview()).isEqualTo("Overview");
        assertThat(p.getTeamComp()).isEqualTo("Team");
        assertThat(p.getRole()).isEqualTo("Role");
        assertThat(p.getAchievement()).isEqualTo("Achievement");

        // Processの検証
        BackupResumeUseCaseDto.ProcessDto proc = p.getProcess();
        assertThat(proc.isRequirements()).isTrue();
        assertThat(proc.isBasicDesign()).isTrue();
        assertThat(proc.isDetailedDesign()).isTrue();
        assertThat(proc.isImplementation()).isTrue();
        assertThat(proc.isIntegrationTest()).isTrue();
        assertThat(proc.isSystemTest()).isTrue();
        assertThat(proc.isMaintenance()).isTrue();

        // TechStackの検証（代表項目）
        BackupResumeUseCaseDto.TechStackDto ts = p.getTechStack();
        assertThat(ts.getFrontend().getLanguages()).isEqualTo(List.of("TypeScript", "JavaScript"));
        assertThat(ts.getBackend().getOrmTools()).isEqualTo(List.of("MyBatis"));
        assertThat(ts.getInfrastructure().getDatabases()).isEqualTo(List.of("PostgreSQL"));
        assertThat(ts.getTools().getSourceControls()).isEqualTo(List.of("Git"));

        // Certificationの検証
        assertThat(r.getCertifications()).hasSize(1);
        BackupResumeUseCaseDto.CertificationDto cert = r.getCertifications().get(0);
        assertThat(cert.getName()).isEqualTo("基本情報技術者");
        assertThat(cert.getDate()).isEqualTo(YearMonth.of(2022, 1));

        // Portfolioの検証
        assertThat(r.getPortfolios()).hasSize(1);
        BackupResumeUseCaseDto.PortfolioDto pf = r.getPortfolios().get(0);
        assertThat(pf.getName()).isEqualTo("PF1");
        assertThat(pf.getOverview()).isEqualTo("overview");
        assertThat(pf.getTechStack()).isEqualTo("tech");
        assertThat(pf.getLink()).isEqualTo("https://portfolio.example");

        // SnsPlatformの検証
        assertThat(r.getSnsPlatforms()).hasSize(1);
        BackupResumeUseCaseDto.SnsPlatformDto sns = r.getSnsPlatforms().get(0);
        assertThat(sns.getName()).isEqualTo("X");
        assertThat(sns.getLink()).isEqualTo("https://x.example");

        // SelfPromotionの検証
        assertThat(r.getSelfPromotions()).hasSize(1);
        BackupResumeUseCaseDto.SelfPromotionDto sp = r.getSelfPromotions().get(0);
        assertThat(sp.getTitle()).isEqualTo("PR1");
        assertThat(sp.getContent()).isEqualTo("content");
    }

    @Test
    @DisplayName("対象の職務経歴書が存在しない場合、UseCaseExceptionがスローされる")
    void test2() {
        when(resumeBackupQuery.findByIdForBackup(RESUME_ID, USER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(resumeBackupQuery).findByIdForBackup(RESUME_ID, USER_ID);
        verify(resumeBackupQuery, never()).findByIdForBackup(RESUME_ID, UUID.randomUUID());
    }

    private static ResumeBackupQueryDto buildQueryDto() {
        ResumeBackupQueryDto.CareerDto career = ResumeBackupQueryDto.CareerDto.builder()
                .companyName("Company")
                .startDate(YearMonth.of(2020, 1))
                .endDate(null)
                .active(true)
                .build();

        ResumeBackupQueryDto.ProcessDto process = ResumeBackupQueryDto.ProcessDto.builder()
                .requirements(true)
                .basicDesign(true)
                .detailedDesign(true)
                .implementation(true)
                .integrationTest(true)
                .systemTest(true)
                .maintenance(true)
                .build();

        ResumeBackupQueryDto.TechStackDto techStack = ResumeBackupQueryDto.TechStackDto.builder()
                .frontend(ResumeBackupQueryDto.FrontendDto.builder()
                        .languages(List.of("TypeScript", "JavaScript"))
                        .frameworks(List.of("React"))
                        .libraries(List.of("Redux"))
                        .buildTools(List.of("Vite"))
                        .packageManagers(List.of("npm"))
                        .linters(List.of("ESLint"))
                        .formatters(List.of("Prettier"))
                        .testingTools(List.of("Jest"))
                        .build())
                .backend(ResumeBackupQueryDto.BackendDto.builder()
                        .languages(List.of("Java"))
                        .frameworks(List.of("Spring Boot"))
                        .libraries(List.of("Jackson"))
                        .buildTools(List.of("Gradle"))
                        .packageManagers(List.of("Maven"))
                        .linters(List.of("Checkstyle"))
                        .formatters(List.of("Spotless"))
                        .testingTools(List.of("JUnit"))
                        .ormTools(List.of("MyBatis"))
                        .auth(List.of("JWT"))
                        .build())
                .infrastructure(ResumeBackupQueryDto.InfrastructureDto.builder()
                        .clouds(List.of("AWS"))
                        .operatingSystems(List.of("Linux"))
                        .containers(List.of("Docker"))
                        .databases(List.of("PostgreSQL"))
                        .webServers(List.of("Nginx"))
                        .ciCdTools(List.of("GitHub Actions"))
                        .iacTools(List.of("Terraform"))
                        .monitoringTools(List.of("CloudWatch"))
                        .loggingTools(List.of("OpenSearch"))
                        .build())
                .tools(ResumeBackupQueryDto.ToolsDto.builder()
                        .sourceControls(List.of("Git"))
                        .projectManagements(List.of("Jira"))
                        .communicationTools(List.of("Slack"))
                        .documentationTools(List.of("Confluence"))
                        .apiDevelopmentTools(List.of("Postman"))
                        .designTools(List.of("Figma"))
                        .editors(List.of("IntelliJ IDEA"))
                        .developmentEnvironments(List.of("Docker Compose"))
                        .build())
                .build();

        ResumeBackupQueryDto.ProjectDto project = ResumeBackupQueryDto.ProjectDto.builder()
                .companyName("Company")
                .startDate(YearMonth.of(2021, 1))
                .endDate(null)
                .active(true)
                .name("Project")
                .overview("Overview")
                .teamComp("Team")
                .role("Role")
                .achievement("Achievement")
                .process(process)
                .techStack(techStack)
                .build();

        ResumeBackupQueryDto.CertificationDto certification = ResumeBackupQueryDto.CertificationDto.builder()
                .name("基本情報技術者")
                .date(YearMonth.of(2022, 1))
                .build();

        ResumeBackupQueryDto.PortfolioDto portfolio = ResumeBackupQueryDto.PortfolioDto.builder()
                .name("PF1")
                .overview("overview")
                .techStack("tech")
                .link("https://portfolio.example")
                .build();

        ResumeBackupQueryDto.SnsPlatformDto snsPlatform = ResumeBackupQueryDto.SnsPlatformDto.builder()
                .name("X")
                .link("https://x.example")
                .build();

        ResumeBackupQueryDto.SelfPromotionDto selfPromotion = ResumeBackupQueryDto.SelfPromotionDto.builder()
                .title("PR1")
                .content("content")
                .build();

        return ResumeBackupQueryDto.builder()
                .resumeName(RESUME_NAME)
                .date(LocalDate.of(2025, 1, 1))
                .lastName("山田")
                .firstName("太郎")
                .careers(List.of(career))
                .projects(List.of(project))
                .certifications(List.of(certification))
                .portfolios(List.of(portfolio))
                .snsPlatforms(List.of(snsPlatform))
                .selfPromotions(List.of(selfPromotion))
                .build();
    }
}
