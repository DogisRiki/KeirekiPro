package com.example.keirekipro.unit.infrastructure.query.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.query.resume.MyBatisResumeBackupQuery;
import com.example.keirekipro.infrastructure.query.resume.ResumeQueryMapper;
import com.example.keirekipro.usecase.query.resume.dto.ResumeBackupQueryDto;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Spy;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class MyBatisResumeBackupQueryTest {

    @Mock
    private ResumeQueryMapper mapper;

    @Spy
    private ObjectMapper objectMapper = new ObjectMapper();

    @InjectMocks
    private MyBatisResumeBackupQuery query;

    private static final UUID USER_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final UUID RESUME_ID = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    @Test
    @DisplayName("バックアップ対象の職務経歴書が存在しない場合、空のOptionalが返る")
    void test1() {
        // モック設定
        when(mapper.selectResumeForBackup(RESUME_ID, USER_ID)).thenReturn(null);

        // 実行
        Optional<ResumeBackupQueryDto> opt = query.findByIdForBackup(RESUME_ID, USER_ID);

        // 検証
        assertThat(opt).isEmpty();
        verify(mapper).selectResumeForBackup(RESUME_ID, USER_ID);
    }

    @Test
    @DisplayName("バックアップ対象の職務経歴書が存在する場合、JSONがDTOに変換されて返る")
    void test2() {
        // モック設定
        String json = """
                {
                    "resumeName":"resume",
                    "date":"2025-01-01",
                    "lastName":"山田",
                    "firstName":"太郎",
                    "careers":[
                        {
                        "companyName":"Company",
                        "startDate":"2020-01-01",
                        "endDate":null,
                        "active":true
                        }
                    ],
                    "projects":[
                        {
                        "companyName":"Company",
                        "startDate":"2021-01-01",
                        "endDate":null,
                        "active":true,
                        "name":"Project",
                        "overview":"Overview",
                        "teamComp":"Team",
                        "role":"Role",
                        "achievement":"Achievement",
                        "process":{
                            "requirements":true,
                            "basicDesign":true,
                            "detailedDesign":true,
                            "implementation":true,
                            "integrationTest":true,
                            "systemTest":true,
                            "maintenance":true
                        },
                        "techStack":{
                            "frontend":{
                            "languages":["TypeScript","JavaScript"],
                            "frameworks":["React"],
                            "libraries":["Redux"],
                            "buildTools":["Vite"],
                            "packageManagers":["npm"],
                            "linters":["ESLint"],
                            "formatters":["Prettier"],
                            "testingTools":["Jest"]
                            },
                            "backend":{
                            "languages":["Java"],
                            "frameworks":["Spring Boot"],
                            "libraries":["Jackson"],
                            "buildTools":["Gradle"],
                            "packageManagers":["Maven"],
                            "linters":["Checkstyle"],
                            "formatters":["Spotless"],
                            "testingTools":["JUnit"],
                            "ormTools":["MyBatis"],
                            "auth":["JWT"]
                            },
                            "infrastructure":{
                            "clouds":["AWS"],
                            "operatingSystems":["Linux"],
                            "containers":["Docker"],
                            "databases":["PostgreSQL"],
                            "webServers":["Nginx"],
                            "ciCdTools":["GitHub Actions"],
                            "iacTools":["Terraform"],
                            "monitoringTools":["CloudWatch"],
                            "loggingTools":["OpenSearch"]
                            },
                            "tools":{
                            "sourceControls":["Git"],
                            "projectManagements":["Jira"],
                            "communicationTools":["Slack"],
                            "documentationTools":["Confluence"],
                            "apiDevelopmentTools":["Postman"],
                            "designTools":["Figma"],
                            "editors":["IntelliJ IDEA"],
                            "developmentEnvironments":["Docker Compose"]
                            }
                        }
                        }
                    ],
                    "certifications":[
                        {
                        "name":"基本情報技術者",
                        "date":"2022-01-01"
                        }
                    ],
                    "portfolios":[
                        {
                        "name":"PF1",
                        "overview":"overview",
                        "techStack":"tech",
                        "link":"https://portfolio.example"
                        }
                    ],
                    "snsPlatforms":[
                        {
                        "name":"X",
                        "link":"https://x.example"
                        }
                    ],
                    "selfPromotions":[
                        {
                        "title":"PR1",
                        "content":"content"
                        }
                    ]
                }
                """;
        when(mapper.selectResumeForBackup(RESUME_ID, USER_ID)).thenReturn(json);

        // 実行
        Optional<ResumeBackupQueryDto> opt = query.findByIdForBackup(RESUME_ID, USER_ID);

        // 親フィールドの検証
        assertThat(opt).isPresent();
        ResumeBackupQueryDto dto = opt.get();
        assertThat(dto.getResumeName()).isEqualTo("resume");
        assertThat(dto.getDate()).isEqualTo(LocalDate.of(2025, 1, 1));
        assertThat(dto.getLastName()).isEqualTo("山田");
        assertThat(dto.getFirstName()).isEqualTo("太郎");

        // Careerの検証
        assertThat(dto.getCareers()).hasSize(1);
        ResumeBackupQueryDto.CareerDto c = dto.getCareers().get(0);
        assertThat(c.getCompanyName()).isEqualTo("Company");
        assertThat(c.getStartDate()).isEqualTo(YearMonth.of(2020, 1));
        assertThat(c.getEndDate()).isNull();
        assertThat(c.isActive()).isTrue();

        // Projectの検証
        assertThat(dto.getProjects()).hasSize(1);
        ResumeBackupQueryDto.ProjectDto p = dto.getProjects().get(0);
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
        ResumeBackupQueryDto.ProcessDto proc = p.getProcess();
        assertThat(proc.isRequirements()).isTrue();
        assertThat(proc.isBasicDesign()).isTrue();
        assertThat(proc.isDetailedDesign()).isTrue();
        assertThat(proc.isImplementation()).isTrue();
        assertThat(proc.isIntegrationTest()).isTrue();
        assertThat(proc.isSystemTest()).isTrue();
        assertThat(proc.isMaintenance()).isTrue();

        // TechStack - Frontend
        ResumeBackupQueryDto.TechStackDto ts = p.getTechStack();
        assertThat(ts.getFrontend().getLanguages()).isEqualTo(List.of("TypeScript", "JavaScript"));
        assertThat(ts.getFrontend().getFrameworks()).isEqualTo(List.of("React"));
        assertThat(ts.getFrontend().getLibraries()).isEqualTo(List.of("Redux"));
        assertThat(ts.getFrontend().getBuildTools()).isEqualTo(List.of("Vite"));
        assertThat(ts.getFrontend().getPackageManagers()).isEqualTo(List.of("npm"));
        assertThat(ts.getFrontend().getLinters()).isEqualTo(List.of("ESLint"));
        assertThat(ts.getFrontend().getFormatters()).isEqualTo(List.of("Prettier"));
        assertThat(ts.getFrontend().getTestingTools()).isEqualTo(List.of("Jest"));

        // TechStack - Backend
        assertThat(ts.getBackend().getLanguages()).isEqualTo(List.of("Java"));
        assertThat(ts.getBackend().getFrameworks()).isEqualTo(List.of("Spring Boot"));
        assertThat(ts.getBackend().getLibraries()).isEqualTo(List.of("Jackson"));
        assertThat(ts.getBackend().getBuildTools()).isEqualTo(List.of("Gradle"));
        assertThat(ts.getBackend().getPackageManagers()).isEqualTo(List.of("Maven"));
        assertThat(ts.getBackend().getLinters()).isEqualTo(List.of("Checkstyle"));
        assertThat(ts.getBackend().getFormatters()).isEqualTo(List.of("Spotless"));
        assertThat(ts.getBackend().getTestingTools()).isEqualTo(List.of("JUnit"));
        assertThat(ts.getBackend().getOrmTools()).isEqualTo(List.of("MyBatis"));
        assertThat(ts.getBackend().getAuth()).isEqualTo(List.of("JWT"));

        // TechStack - Infrastructure
        assertThat(ts.getInfrastructure().getClouds()).isEqualTo(List.of("AWS"));
        assertThat(ts.getInfrastructure().getOperatingSystems()).isEqualTo(List.of("Linux"));
        assertThat(ts.getInfrastructure().getContainers()).isEqualTo(List.of("Docker"));
        assertThat(ts.getInfrastructure().getDatabases()).isEqualTo(List.of("PostgreSQL"));
        assertThat(ts.getInfrastructure().getWebServers()).isEqualTo(List.of("Nginx"));
        assertThat(ts.getInfrastructure().getCiCdTools()).isEqualTo(List.of("GitHub Actions"));
        assertThat(ts.getInfrastructure().getIacTools()).isEqualTo(List.of("Terraform"));
        assertThat(ts.getInfrastructure().getMonitoringTools()).isEqualTo(List.of("CloudWatch"));
        assertThat(ts.getInfrastructure().getLoggingTools()).isEqualTo(List.of("OpenSearch"));

        // TechStack - Tools
        assertThat(ts.getTools().getSourceControls()).isEqualTo(List.of("Git"));
        assertThat(ts.getTools().getProjectManagements()).isEqualTo(List.of("Jira"));
        assertThat(ts.getTools().getCommunicationTools()).isEqualTo(List.of("Slack"));
        assertThat(ts.getTools().getDocumentationTools()).isEqualTo(List.of("Confluence"));
        assertThat(ts.getTools().getApiDevelopmentTools()).isEqualTo(List.of("Postman"));
        assertThat(ts.getTools().getDesignTools()).isEqualTo(List.of("Figma"));
        assertThat(ts.getTools().getEditors()).isEqualTo(List.of("IntelliJ IDEA"));
        assertThat(ts.getTools().getDevelopmentEnvironments()).isEqualTo(List.of("Docker Compose"));

        // Certificationの検証
        assertThat(dto.getCertifications()).hasSize(1);
        ResumeBackupQueryDto.CertificationDto cert = dto.getCertifications().get(0);
        assertThat(cert.getName()).isEqualTo("基本情報技術者");
        assertThat(cert.getDate()).isEqualTo(YearMonth.of(2022, 1));

        // Portfolioの検証
        assertThat(dto.getPortfolios()).hasSize(1);
        ResumeBackupQueryDto.PortfolioDto pf = dto.getPortfolios().get(0);
        assertThat(pf.getName()).isEqualTo("PF1");
        assertThat(pf.getOverview()).isEqualTo("overview");
        assertThat(pf.getTechStack()).isEqualTo("tech");
        assertThat(pf.getLink()).isEqualTo("https://portfolio.example");

        // SnsPlatformの検証
        assertThat(dto.getSnsPlatforms()).hasSize(1);
        ResumeBackupQueryDto.SnsPlatformDto sns = dto.getSnsPlatforms().get(0);
        assertThat(sns.getName()).isEqualTo("X");
        assertThat(sns.getLink()).isEqualTo("https://x.example");

        // SelfPromotionの検証
        assertThat(dto.getSelfPromotions()).hasSize(1);
        ResumeBackupQueryDto.SelfPromotionDto sp = dto.getSelfPromotions().get(0);
        assertThat(sp.getTitle()).isEqualTo("PR1");
        assertThat(sp.getContent()).isEqualTo("content");

        verify(mapper).selectResumeForBackup(RESUME_ID, USER_ID);
    }

    @Test
    @DisplayName("JSONのパースに失敗した場合、IllegalStateExceptionが送出される")
    void test3() {
        // モック設定
        when(mapper.selectResumeForBackup(RESUME_ID, USER_ID)).thenReturn("{");

        // 実行・検証
        assertThatThrownBy(() -> query.findByIdForBackup(RESUME_ID, USER_ID))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("バックアップデータのパースに失敗しました");

        verify(mapper).selectResumeForBackup(RESUME_ID, USER_ID);
    }
}
