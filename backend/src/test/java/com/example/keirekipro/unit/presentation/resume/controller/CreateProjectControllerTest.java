package com.example.keirekipro.unit.presentation.resume.controller;

import static org.hamcrest.Matchers.hasItem;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.presentation.resume.controller.CreateProjectController;
import com.example.keirekipro.presentation.resume.dto.CreateProjectRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.CreateProjectUseCase;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
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

@WebMvcTest(CreateProjectController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class CreateProjectControllerTest {

    @MockitoBean
    private CreateProjectUseCase useCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;
    private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

    private static final String ENDPOINT = "/api/resumes/{resumeId}/projects";
    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID RESUME_DTO_ID = UUID.fromString("33333333-3333-3333-3333-333333333333");

    private static final String RESUME_NAME = "職務経歴書テスト";
    private static final LocalDate DATE = LocalDate.of(2021, 5, 20);
    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2021, 5, 15, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2021, 5, 18, 15, 30);

    private static final DateTimeFormatter FMT = DateTimeFormatter.ISO_LOCAL_DATE_TIME;

    private static CreateProjectRequest buildValidRequest() {
        CreateProjectRequest req = new CreateProjectRequest();

        req.setCompanyName("株式会社テスト");
        req.setStartDate(YearMonth.of(2021, 1));
        req.setEndDate(null);
        req.setIsActive(true);

        req.setName("プロジェクト名");
        req.setOverview("プロジェクト概要");
        req.setTeamComp("5名");
        req.setRole("役割");
        req.setAchievement("成果");

        req.setRequirements(true);
        req.setBasicDesign(true);
        req.setDetailedDesign(true);
        req.setImplementation(true);
        req.setIntegrationTest(true);
        req.setSystemTest(true);
        req.setMaintenance(true);

        req.setFrontendLanguages(List.of("TypeScript"));
        req.setFrontendFrameworks(List.of("React"));
        req.setFrontendLibraries(List.of());
        req.setFrontendBuildTools(List.of());
        req.setFrontendPackageManagers(List.of());
        req.setFrontendLinters(List.of());
        req.setFrontendFormatters(List.of());
        req.setFrontendTestingTools(List.of());

        req.setBackendLanguages(List.of("Java"));
        req.setBackendFrameworks(List.of("Spring Boot"));
        req.setBackendLibraries(List.of());
        req.setBackendBuildTools(List.of());
        req.setBackendPackageManagers(List.of());
        req.setBackendLinters(List.of());
        req.setBackendFormatters(List.of());
        req.setBackendTestingTools(List.of());
        req.setOrmTools(List.of());
        req.setAuth(List.of());

        req.setClouds(List.of("AWS"));
        req.setOperatingSystems(List.of("Linux"));
        req.setContainers(List.of("Docker"));
        req.setDatabases(List.of("PostgreSQL"));
        req.setWebServers(List.of("Nginx"));
        req.setCiCdTools(List.of("Jenkins"));
        req.setIacTools(List.of());
        req.setMonitoringTools(List.of());
        req.setLoggingTools(List.of());

        req.setSourceControls(List.of("Git"));
        req.setProjectManagements(List.of());
        req.setCommunicationTools(List.of());
        req.setDocumentationTools(List.of());
        req.setApiDevelopmentTools(List.of());
        req.setDesignTools(List.of());
        req.setEditors(List.of("IntelliJ"));
        req.setDevelopmentEnvironments(List.of());

        return req;
    }

    @Test
    @DisplayName("正常なリクエストの場合、201と職務経歴書情報がレスポンスとして返る")
    void test1() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        String body = objectMapper.writeValueAsString(req);

        ResumeInfoUseCaseDto dto = ResumeObjectBuilder.buildResumeInfoUseCaseDto(
                RESUME_DTO_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(useCase.execute(eq(USER_ID), eq(RESUME_ID), any(CreateProjectRequest.class))).thenReturn(dto);

        mockMvc.perform(post(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(dto.getId().toString()))
                .andExpect(jsonPath("$.createdAt").value(CREATED_AT.format(FMT)))
                .andExpect(jsonPath("$.updatedAt").value(UPDATED_AT.format(FMT)));

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID), eq(RESUME_ID), any(CreateProjectRequest.class));
    }

    @Test
    @DisplayName("会社名が空の場合、バリデーションエラーとなる")
    void test2() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setCompanyName("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.companyName").isArray())
                .andExpect(jsonPath("$.errors.companyName", hasItem("会社名は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("会社名が50文字超の場合、バリデーションエラーとなる")
    void test3() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setCompanyName("a".repeat(51));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.companyName").isArray())
                .andExpect(jsonPath("$.errors.companyName", hasItem("会社名は50文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("開始年月がnullの場合、バリデーションエラーとなる")
    void test4() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setStartDate(null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.startDate").isArray())
                .andExpect(jsonPath("$.errors.startDate", hasItem("開始年月は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("継続中がnullの場合、バリデーションエラーとなる")
    void test5() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setIsActive(null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.isActive").isArray())
                .andExpect(jsonPath("$.errors.isActive", hasItem("継続中は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("プロジェクト名が空の場合、バリデーションエラーとなる")
    void test6() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setName("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.name").isArray())
                .andExpect(jsonPath("$.errors.name", hasItem("プロジェクト名は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("プロジェクト名が50文字超の場合、バリデーションエラーとなる")
    void test7() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setName("a".repeat(51));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.name").isArray())
                .andExpect(jsonPath("$.errors.name", hasItem("プロジェクト名は50文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("プロジェクト概要が空の場合、バリデーションエラーとなる")
    void test8() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setOverview("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.overview").isArray())
                .andExpect(jsonPath("$.errors.overview", hasItem("プロジェクト概要は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("プロジェクト概要が1000文字超の場合、バリデーションエラーとなる")
    void test9() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setOverview("a".repeat(1001));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.overview").isArray())
                .andExpect(jsonPath("$.errors.overview", hasItem("プロジェクト概要は1000文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("チーム構成が空の場合、バリデーションエラーとなる")
    void test10() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setTeamComp("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.teamComp").isArray())
                .andExpect(jsonPath("$.errors.teamComp", hasItem("チーム構成は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("チーム構成が100文字超の場合、バリデーションエラーとなる")
    void test11() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setTeamComp("a".repeat(101));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.teamComp").isArray())
                .andExpect(jsonPath("$.errors.teamComp", hasItem("チーム構成は100文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("役割が空の場合、バリデーションエラーとなる")
    void test12() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setRole("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.role").isArray())
                .andExpect(jsonPath("$.errors.role", hasItem("役割は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("役割が1000文字超の場合、バリデーションエラーとなる")
    void test13() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setRole("a".repeat(1001));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.role").isArray())
                .andExpect(jsonPath("$.errors.role", hasItem("役割は1000文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("成果が空の場合、バリデーションエラーとなる")
    void test14() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setAchievement("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.achievement").isArray())
                .andExpect(jsonPath("$.errors.achievement", hasItem("成果は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("成果が1000文字超の場合、バリデーションエラーとなる")
    void test15() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setAchievement("a".repeat(1001));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.achievement").isArray())
                .andExpect(jsonPath("$.errors.achievement", hasItem("成果は1000文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("作業工程 requirements がnullの場合、バリデーションエラーとなる")
    void test16() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setRequirements(null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.requirements").isArray());

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("作業工程 basicDesign がnullの場合、バリデーションエラーとなる")
    void test17() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setBasicDesign(null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.basicDesign").isArray());

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("作業工程 detailedDesign がnullの場合、バリデーションエラーとなる")
    void test18() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setDetailedDesign(null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.detailedDesign").isArray());

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("作業工程 implementation がnullの場合、バリデーションエラーとなる")
    void test19() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setImplementation(null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.implementation").isArray());

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("作業工程 integrationTest がnullの場合、バリデーションエラーとなる")
    void test20() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setIntegrationTest(null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.integrationTest").isArray());

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("作業工程 systemTest がnullの場合、バリデーションエラーとなる")
    void test21() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setSystemTest(null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.systemTest").isArray());

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("作業工程 maintenance がnullの場合、バリデーションエラーとなる")
    void test22() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setMaintenance(null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.maintenance").isArray());

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("開始年月の年が1900未満の場合、バリデーションエラーとなる")
    void test23() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setStartDate(YearMonth.of(1899, 12));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.startDate").isArray())
                .andExpect(jsonPath("$.errors.startDate", hasItem("開始年月が不正です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("開始年月の年が2100超の場合、バリデーションエラーとなる")
    void test24() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setStartDate(YearMonth.of(2101, 1));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.startDate").isArray())
                .andExpect(jsonPath("$.errors.startDate", hasItem("開始年月が不正です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("終了年月の年が1900未満の場合、バリデーションエラーとなる")
    void test25() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setEndDate(YearMonth.of(1899, 12));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.endDate").isArray())
                .andExpect(jsonPath("$.errors.endDate", hasItem("終了年月が不正です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("終了年月の年が2100超の場合、バリデーションエラーとなる")
    void test26() throws Exception {
        CreateProjectRequest req = buildValidRequest();
        req.setEndDate(YearMonth.of(2101, 1));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.endDate").isArray())
                .andExpect(jsonPath("$.errors.endDate", hasItem("終了年月が不正です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }
}
