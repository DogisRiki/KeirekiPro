package com.example.keirekipro.unit.presentation.resume.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.presentation.resume.controller.RestoreResumeController;
import com.example.keirekipro.presentation.resume.dto.RestoreResumeRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.RestoreResumeUseCase;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.resume.policy.ResumeBackupVersion;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestConstructor.AutowireMode;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(RestoreResumeController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class RestoreResumeControllerTest {

    @MockitoBean
    private RestoreResumeUseCase restoreResumeUseCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;
    private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

    private static final String ENDPOINT = "/api/resumes/restore";

    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_DTO_ID = UUID.fromString("33333333-3333-3333-3333-333333333333");

    private static final String RESUME_NAME = "職務経歴書1";
    private static final LocalDate DATE = LocalDate.of(2025, 1, 1);
    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";

    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2025, 1, 2, 10, 0, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2025, 1, 3, 11, 30, 0);

    private static final DateTimeFormatter FMT = DateTimeFormatter.ISO_LOCAL_DATE_TIME;

    private static RestoreResumeRequest buildValidRequest() {
        RestoreResumeRequest.CareerDto career = new RestoreResumeRequest.CareerDto(
                "Company",
                YearMonth.of(2020, 1),
                null,
                true);

        RestoreResumeRequest.ProcessDto process = new RestoreResumeRequest.ProcessDto(
                true, true, true, true, true, true, true);

        RestoreResumeRequest.TechStackDto techStack = new RestoreResumeRequest.TechStackDto(
                new RestoreResumeRequest.FrontendDto(
                        List.of("TypeScript", "JavaScript"),
                        List.of("React"),
                        List.of("Redux"),
                        List.of("Vite"),
                        List.of("npm"),
                        List.of("ESLint"),
                        List.of("Prettier"),
                        List.of("Jest")),
                new RestoreResumeRequest.BackendDto(
                        List.of("Java"),
                        List.of("Spring Boot"),
                        List.of("Jackson"),
                        List.of("Gradle"),
                        List.of("Maven"),
                        List.of("Checkstyle"),
                        List.of("Spotless"),
                        List.of("JUnit"),
                        List.of("MyBatis"),
                        List.of("JWT")),
                new RestoreResumeRequest.InfrastructureDto(
                        List.of("AWS"),
                        List.of("Linux"),
                        List.of("Docker"),
                        List.of("PostgreSQL"),
                        List.of("Nginx"),
                        List.of("GitHub Actions"),
                        List.of("Terraform"),
                        List.of("CloudWatch"),
                        List.of("OpenSearch")),
                new RestoreResumeRequest.ToolsDto(
                        List.of("Git"),
                        List.of("Jira"),
                        List.of("Slack"),
                        List.of("Confluence"),
                        List.of("Postman"),
                        List.of("Figma"),
                        List.of("IntelliJ IDEA"),
                        List.of("Docker Compose")));

        RestoreResumeRequest.ProjectDto project = new RestoreResumeRequest.ProjectDto(
                "Company",
                YearMonth.of(2021, 1),
                null,
                true,
                "Project",
                "Overview",
                "Team",
                "Role",
                "Achievement",
                process,
                techStack);

        RestoreResumeRequest.CertificationDto certification = new RestoreResumeRequest.CertificationDto(
                "基本情報技術者",
                YearMonth.of(2022, 1));

        RestoreResumeRequest.PortfolioDto portfolio = new RestoreResumeRequest.PortfolioDto(
                "PF1",
                "overview",
                "tech",
                "https://portfolio.example");

        RestoreResumeRequest.SnsPlatformDto snsPlatform = new RestoreResumeRequest.SnsPlatformDto(
                "X",
                "https://x.example");

        RestoreResumeRequest.SelfPromotionDto selfPromotion = new RestoreResumeRequest.SelfPromotionDto(
                "PR1",
                "content");

        RestoreResumeRequest.ResumeDto resume = new RestoreResumeRequest.ResumeDto(
                RESUME_NAME,
                DATE,
                LAST_NAME,
                FIRST_NAME,
                List.of(career),
                List.of(project),
                List.of(certification),
                List.of(portfolio),
                List.of(snsPlatform),
                List.of(selfPromotion));

        return new RestoreResumeRequest(
                ResumeBackupVersion.SUPPORTED_VERSION,
                Instant.parse("2025-01-01T00:00:00Z"),
                resume);
    }

    @Test
    @DisplayName("正常なリクエストの場合、201と完全な職務経歴書情報がレスポンスとして返る")
    void test1() throws Exception {
        // リクエスト作成（全項目を設定）
        RestoreResumeRequest req = buildValidRequest();
        String body = objectMapper.writeValueAsString(req);

        // UseCase戻り値DTO（参考実装に倣いヘルパーで作成）
        ResumeInfoUseCaseDto dto = ResumeObjectBuilder.buildResumeInfoUseCaseDto(
                RESUME_DTO_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(restoreResumeUseCase.execute(eq(USER_ID), any(RestoreResumeRequest.class))).thenReturn(dto);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(dto.getId().toString()))
                .andExpect(jsonPath("$.resumeName").value(RESUME_NAME))
                .andExpect(jsonPath("$.date").value(DATE.toString()))
                .andExpect(jsonPath("$.lastName").value(LAST_NAME))
                .andExpect(jsonPath("$.firstName").value(FIRST_NAME))
                .andExpect(jsonPath("$.createdAt").value(CREATED_AT.format(FMT)))
                .andExpect(jsonPath("$.updatedAt").value(UPDATED_AT.format(FMT)))
                .andExpect(jsonPath("$.careers.length()").value(1))
                .andExpect(jsonPath("$.projects.length()").value(1))
                .andExpect(jsonPath("$.certifications.length()").value(1))
                .andExpect(jsonPath("$.portfolios.length()").value(1))
                .andExpect(jsonPath("$.snsPlatforms.length()").value(1))
                .andExpect(jsonPath("$.selfPromotions.length()").value(1));

        verify(currentUserFacade).getUserId();
        verify(restoreResumeUseCase).execute(eq(USER_ID), any(RestoreResumeRequest.class));
    }
}
