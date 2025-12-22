package com.example.keirekipro.unit.presentation.resume.controller;

import static org.hamcrest.Matchers.hasItem;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.presentation.resume.controller.UpdateProjectController;
import com.example.keirekipro.presentation.resume.dto.UpdateProjectRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.UpdateProjectUseCase;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

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

@WebMvcTest(UpdateProjectController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class UpdateProjectControllerTest {

    @MockitoBean
    private UpdateProjectUseCase useCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;
    private final ObjectMapper objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());

    private static final String ENDPOINT = "/api/resumes/{resumeId}/projects/{projectId}";
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID PROJECT_ID = UUID.fromString("66666666-6666-6666-6666-666666666666");
    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final String RESUME_NAME = "職務経歴書テスト";
    private static final LocalDate DATE = LocalDate.of(2021, 5, 20);
    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2021, 5, 15, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2021, 5, 18, 15, 30);
    private static final DateTimeFormatter FMT = DateTimeFormatter.ISO_LOCAL_DATE_TIME;

    private UpdateProjectRequest createValidProjectRequest() {
        UpdateProjectRequest req = new UpdateProjectRequest();

        req.setCompanyName("株式会社テスト");
        req.setStartDate(YearMonth.of(2020, 1));
        req.setEndDate(YearMonth.of(2021, 12));
        req.setIsActive(Boolean.TRUE);

        req.setName("プロジェクト名");
        req.setOverview("プロジェクト概要");
        req.setTeamComp("チーム構成");
        req.setRole("役割");
        req.setAchievement("成果");

        // 作業工程
        req.setRequirements(Boolean.TRUE);
        req.setBasicDesign(Boolean.TRUE);
        req.setDetailedDesign(Boolean.TRUE);
        req.setImplementation(Boolean.TRUE);
        req.setIntegrationTest(Boolean.TRUE);
        req.setSystemTest(Boolean.TRUE);
        req.setMaintenance(Boolean.TRUE);

        // TechStack - Frontend
        req.setFrontendLanguages(List.of("Java"));
        req.setFrontendFrameworks(List.of("Spring Boot"));
        req.setFrontendLibraries(List.of("Spring Security"));
        req.setFrontendBuildTools(List.of("Maven"));
        req.setFrontendPackageManagers(List.of("npm"));
        req.setFrontendLinters(List.of("ESLint"));
        req.setFrontendFormatters(List.of("Prettier"));
        req.setFrontendTestingTools(List.of("Jest"));

        // TechStack - Backend
        req.setBackendLanguages(List.of("Java"));
        req.setBackendFrameworks(List.of("Spring Boot"));
        req.setBackendLibraries(List.of("Lombok"));
        req.setBackendBuildTools(List.of("Gradle"));
        req.setBackendPackageManagers(List.of("npm"));
        req.setBackendLinters(List.of("Checkstyle"));
        req.setBackendFormatters(List.of("Spotless"));
        req.setBackendTestingTools(List.of("JUnit5"));
        req.setOrmTools(List.of("Hibernate"));
        req.setAuth(List.of("OAuth2"));

        // TechStack - Infrastructure
        req.setClouds(List.of("AWS"));
        req.setOperatingSystems(List.of("Linux"));
        req.setContainers(List.of("Docker"));
        req.setDatabases(List.of("PostgreSQL"));
        req.setWebServers(List.of("nginx"));
        req.setCiCdTools(List.of("GitHub Actions"));
        req.setIacTools(List.of("Terraform"));
        req.setMonitoringTools(List.of("CloudWatch"));
        req.setLoggingTools(List.of("CloudWatch Logs"));

        // TechStack - Tools
        req.setSourceControls(List.of("Git"));
        req.setProjectManagements(List.of("Jira"));
        req.setCommunicationTools(List.of("Slack"));
        req.setDocumentationTools(List.of("Confluence"));
        req.setApiDevelopmentTools(List.of("Postman"));
        req.setDesignTools(List.of("Figma"));
        req.setEditors(List.of("IntelliJ IDEA"));
        req.setDevelopmentEnvironments(List.of("Docker Desktop"));

        return req;
    }

    @Test
    @DisplayName("正常なリクエストの場合、200と更新後の職務経歴書情報が返る")
    void test1() throws Exception {
        // リクエスト作成
        UpdateProjectRequest req = createValidProjectRequest();
        String body = objectMapper.writeValueAsString(req);

        // UseCaseDtoを生成
        ResumeInfoUseCaseDto dto = ResumeObjectBuilder.buildResumeInfoUseCaseDto(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        // モック設定
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(useCase.execute(eq(USER_ID), eq(RESUME_ID), eq(PROJECT_ID), any(UpdateProjectRequest.class)))
                .thenReturn(dto);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(RESUME_ID.toString()))
                .andExpect(jsonPath("$.resumeName").value(RESUME_NAME))
                .andExpect(jsonPath("$.date").value(DATE.toString()))
                .andExpect(jsonPath("$.createdAt").value(CREATED_AT.format(FMT)))
                .andExpect(jsonPath("$.updatedAt").value(UPDATED_AT.format(FMT)))
                // ヘルパー実装どおり１件ずつ入っていることをチェック
                .andExpect(jsonPath("$.careers.length()").value(1))
                .andExpect(jsonPath("$.projects.length()").value(1))
                .andExpect(jsonPath("$.certifications.length()").value(1))
                .andExpect(jsonPath("$.portfolios.length()").value(1))
                .andExpect(jsonPath("$.snsPlatforms.length()").value(1))
                .andExpect(jsonPath("$.selfPromotions.length()").value(1));

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID), eq(RESUME_ID), eq(PROJECT_ID),
                any(UpdateProjectRequest.class));
    }

    @Test
    @DisplayName("会社名が空の場合、バリデーションエラーとなる")
    void test2() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setCompanyName("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.companyName").isArray())
                .andExpect(jsonPath("$.errors.companyName",
                        hasItem("会社名は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("会社名が50文字超の場合、バリデーションエラーとなる")
    void test3() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setCompanyName("a".repeat(51));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.companyName").isArray())
                .andExpect(jsonPath("$.errors.companyName",
                        hasItem("会社名は50文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("開始年月がnullの場合、バリデーションエラーとなる")
    void test4() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setStartDate(null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.startDate").isArray())
                .andExpect(jsonPath("$.errors.startDate",
                        hasItem("開始年月は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("継続中フラグがnullの場合、バリデーションエラーとなる")
    void test5() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setIsActive(null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.isActive").isArray())
                .andExpect(jsonPath("$.errors.isActive",
                        hasItem("継続中は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("プロジェクト名が空の場合、バリデーションエラーとなる")
    void test6() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setName("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.name").isArray())
                .andExpect(jsonPath("$.errors.name",
                        hasItem("プロジェクト名は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("プロジェクト名が50文字超の場合、バリデーションエラーとなる")
    void test7() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setName("a".repeat(51));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.name").isArray())
                .andExpect(jsonPath("$.errors.name",
                        hasItem("プロジェクト名は50文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("プロジェクト概要が空の場合、バリデーションエラーとなる")
    void test8() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setOverview("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.overview").isArray())
                .andExpect(jsonPath("$.errors.overview",
                        hasItem("プロジェクト概要は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("プロジェクト概要が1000文字超の場合、バリデーションエラーとなる")
    void test9() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setOverview("a".repeat(1001));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.overview").isArray())
                .andExpect(jsonPath("$.errors.overview",
                        hasItem("プロジェクト概要は1000文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("チーム構成が空の場合、バリデーションエラーとなる")
    void test10() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setTeamComp("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.teamComp").isArray())
                .andExpect(jsonPath("$.errors.teamComp",
                        hasItem("チーム構成は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("チーム構成が100文字超の場合、バリデーションエラーとなる")
    void test11() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setTeamComp("a".repeat(101));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.teamComp").isArray())
                .andExpect(jsonPath("$.errors.teamComp",
                        hasItem("チーム構成は100文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("役割が空の場合、バリデーションエラーとなる")
    void test12() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setRole("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.role").isArray())
                .andExpect(jsonPath("$.errors.role",
                        hasItem("役割は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("役割が1000文字超の場合、バリデーションエラーとなる")
    void test13() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setRole("a".repeat(1001));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.role").isArray())
                .andExpect(jsonPath("$.errors.role",
                        hasItem("役割は1000文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("成果が空の場合、バリデーションエラーとなる")
    void test14() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setAchievement("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.achievement").isArray())
                .andExpect(jsonPath("$.errors.achievement",
                        hasItem("成果は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("成果が1000文字超の場合、バリデーションエラーとなる")
    void test15() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setAchievement("a".repeat(1001));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.achievement").isArray())
                .andExpect(jsonPath("$.errors.achievement",
                        hasItem("成果は1000文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("開始年月の年が1900未満の場合、バリデーションエラーとなる")
    void test16() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setStartDate(YearMonth.of(1899, 12));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.startDate").isArray())
                .andExpect(jsonPath("$.errors.startDate", hasItem("開始年月が不正です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("開始年月の年が2100超の場合、バリデーションエラーとなる")
    void test17() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setStartDate(YearMonth.of(2101, 1));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.startDate").isArray())
                .andExpect(jsonPath("$.errors.startDate", hasItem("開始年月が不正です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("終了年月の年が1900未満の場合、バリデーションエラーとなる")
    void test18() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setEndDate(YearMonth.of(1899, 12));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.endDate").isArray())
                .andExpect(jsonPath("$.errors.endDate", hasItem("終了年月が不正です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("終了年月の年が2100超の場合、バリデーションエラーとなる")
    void test19() throws Exception {
        UpdateProjectRequest req = createValidProjectRequest();
        req.setEndDate(YearMonth.of(2101, 1));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, PROJECT_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.endDate").isArray())
                .andExpect(jsonPath("$.errors.endDate", hasItem("終了年月が不正です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }
}
