package com.example.keirekipro.unit.presentation.resume.controller;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.presentation.resume.controller.BackupResumeController;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.BackupResumeUseCase;
import com.example.keirekipro.usecase.resume.dto.BackupResumeUseCaseDto;
import com.example.keirekipro.usecase.resume.policy.ResumeBackupVersion;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestConstructor.AutowireMode;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(BackupResumeController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class BackupResumeControllerTest {

    @MockitoBean
    private BackupResumeUseCase useCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/resumes/{resumeId}/backup";
    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");

    private static final String RESUME_NAME = "職務経歴書1";

    private static BackupResumeUseCaseDto buildUseCaseDto(Instant exportedAt) {
        BackupResumeUseCaseDto.CareerDto career = BackupResumeUseCaseDto.CareerDto.builder()
                .companyName("Company")
                .startDate(YearMonth.of(2020, 1))
                .endDate(null)
                .active(true)
                .build();

        BackupResumeUseCaseDto.ProcessDto process = BackupResumeUseCaseDto.ProcessDto.builder()
                .requirements(true)
                .basicDesign(true)
                .detailedDesign(true)
                .implementation(true)
                .integrationTest(true)
                .systemTest(true)
                .maintenance(true)
                .build();

        BackupResumeUseCaseDto.TechStackDto techStack = BackupResumeUseCaseDto.TechStackDto.builder()
                .frontend(BackupResumeUseCaseDto.FrontendDto.builder()
                        .languages(List.of("TypeScript", "JavaScript"))
                        .frameworks(List.of("React"))
                        .libraries(List.of("Redux"))
                        .buildTools(List.of("Vite"))
                        .packageManagers(List.of("npm"))
                        .linters(List.of("ESLint"))
                        .formatters(List.of("Prettier"))
                        .testingTools(List.of("Jest"))
                        .build())
                .backend(BackupResumeUseCaseDto.BackendDto.builder()
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
                .infrastructure(BackupResumeUseCaseDto.InfrastructureDto.builder()
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
                .tools(BackupResumeUseCaseDto.ToolsDto.builder()
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

        BackupResumeUseCaseDto.ProjectDto project = BackupResumeUseCaseDto.ProjectDto.builder()
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

        BackupResumeUseCaseDto.CertificationDto certification = BackupResumeUseCaseDto.CertificationDto.builder()
                .name("基本情報技術者")
                .date(YearMonth.of(2022, 1))
                .build();

        BackupResumeUseCaseDto.PortfolioDto portfolio = BackupResumeUseCaseDto.PortfolioDto.builder()
                .name("PF1")
                .overview("overview")
                .techStack("tech")
                .link("https://portfolio.example")
                .build();

        BackupResumeUseCaseDto.SnsPlatformDto snsPlatform = BackupResumeUseCaseDto.SnsPlatformDto.builder()
                .name("X")
                .link("https://x.example")
                .build();

        BackupResumeUseCaseDto.SelfPromotionDto selfPromotion = BackupResumeUseCaseDto.SelfPromotionDto.builder()
                .title("PR1")
                .content("content")
                .build();

        BackupResumeUseCaseDto.ResumeDto resume = BackupResumeUseCaseDto.ResumeDto.builder()
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

        return BackupResumeUseCaseDto.builder()
                .fileName("職務経歴書1_backup.json")
                .contentType(MediaType.APPLICATION_JSON_VALUE)
                .version(ResumeBackupVersion.SUPPORTED_VERSION)
                .exportedAt(exportedAt)
                .resume(resume)
                .build();
    }

    @Test
    @DisplayName("正常なリクエストの場合、200とバックアップJSONがレスポンスとして返る（Content-DispositionはRFC5987形式）")
    void test1() throws Exception {
        Instant exportedAt = Instant.parse("2025-01-01T00:00:00Z");
        BackupResumeUseCaseDto dto = buildUseCaseDto(exportedAt);

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(useCase.execute(eq(USER_ID), eq(RESUME_ID))).thenReturn(dto);

        mockMvc.perform(get(ENDPOINT, RESUME_ID))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE))
                .andExpect(header().string(HttpHeaders.CONTENT_DISPOSITION, containsString("attachment")))
                .andExpect(header().string(HttpHeaders.CONTENT_DISPOSITION, containsString("filename*=")))
                // ルート項目
                .andExpect(jsonPath("$.version").value(dto.getVersion()))
                .andExpect(jsonPath("$.exportedAt").value(exportedAt.toString()))
                // resume（親フィールド）
                .andExpect(jsonPath("$.resume.resumeName").value(RESUME_NAME))
                .andExpect(jsonPath("$.resume.date").value("2025-01-01"))
                .andExpect(jsonPath("$.resume.lastName").value("山田"))
                .andExpect(jsonPath("$.resume.firstName").value("太郎"))
                // careers
                .andExpect(jsonPath("$.resume.careers.length()").value(1))
                .andExpect(jsonPath("$.resume.careers[0].companyName").value("Company"))
                .andExpect(jsonPath("$.resume.careers[0].startDate").value("2020-01"))
                .andExpect(jsonPath("$.resume.careers[0].endDate").doesNotExist())
                .andExpect(jsonPath("$.resume.careers[0].active").value(true))
                // projects（代表項目＋ネスト）
                .andExpect(jsonPath("$.resume.projects.length()").value(1))
                .andExpect(jsonPath("$.resume.projects[0].companyName").value("Company"))
                .andExpect(jsonPath("$.resume.projects[0].startDate").value("2021-01"))
                .andExpect(jsonPath("$.resume.projects[0].endDate").doesNotExist())
                .andExpect(jsonPath("$.resume.projects[0].active").value(true))
                .andExpect(jsonPath("$.resume.projects[0].name").value("Project"))
                .andExpect(jsonPath("$.resume.projects[0].overview").value("Overview"))
                .andExpect(jsonPath("$.resume.projects[0].teamComp").value("Team"))
                .andExpect(jsonPath("$.resume.projects[0].role").value("Role"))
                .andExpect(jsonPath("$.resume.projects[0].achievement").value("Achievement"))
                // process
                .andExpect(jsonPath("$.resume.projects[0].process.requirements").value(true))
                .andExpect(jsonPath("$.resume.projects[0].process.basicDesign").value(true))
                .andExpect(jsonPath("$.resume.projects[0].process.detailedDesign").value(true))
                .andExpect(jsonPath("$.resume.projects[0].process.implementation").value(true))
                .andExpect(jsonPath("$.resume.projects[0].process.integrationTest").value(true))
                .andExpect(jsonPath("$.resume.projects[0].process.systemTest").value(true))
                .andExpect(jsonPath("$.resume.projects[0].process.maintenance").value(true))
                // techStack（代表項目）
                .andExpect(jsonPath("$.resume.projects[0].techStack.frontend.languages[0]").value("TypeScript"))
                .andExpect(jsonPath("$.resume.projects[0].techStack.frontend.languages[1]").value("JavaScript"))
                .andExpect(jsonPath("$.resume.projects[0].techStack.backend.ormTools[0]").value("MyBatis"))
                .andExpect(jsonPath("$.resume.projects[0].techStack.infrastructure.databases[0]").value("PostgreSQL"))
                .andExpect(jsonPath("$.resume.projects[0].techStack.tools.sourceControls[0]").value("Git"))
                // certifications
                .andExpect(jsonPath("$.resume.certifications.length()").value(1))
                .andExpect(jsonPath("$.resume.certifications[0].name").value("基本情報技術者"))
                .andExpect(jsonPath("$.resume.certifications[0].date").value("2022-01"))
                // portfolios
                .andExpect(jsonPath("$.resume.portfolios.length()").value(1))
                .andExpect(jsonPath("$.resume.portfolios[0].name").value("PF1"))
                .andExpect(jsonPath("$.resume.portfolios[0].overview").value("overview"))
                .andExpect(jsonPath("$.resume.portfolios[0].techStack").value("tech"))
                .andExpect(jsonPath("$.resume.portfolios[0].link").value("https://portfolio.example"))
                // snsPlatforms
                .andExpect(jsonPath("$.resume.snsPlatforms.length()").value(1))
                .andExpect(jsonPath("$.resume.snsPlatforms[0].name").value("X"))
                .andExpect(jsonPath("$.resume.snsPlatforms[0].link").value("https://x.example"))
                // selfPromotions
                .andExpect(jsonPath("$.resume.selfPromotions.length()").value(1))
                .andExpect(jsonPath("$.resume.selfPromotions[0].title").value("PR1"))
                .andExpect(jsonPath("$.resume.selfPromotions[0].content").value("content"));

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID), eq(RESUME_ID));
    }
}
