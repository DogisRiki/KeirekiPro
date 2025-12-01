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
import com.example.keirekipro.presentation.resume.controller.UpdateCertificationsController;
import com.example.keirekipro.presentation.resume.dto.UpdateCertificationsRequest;
import com.example.keirekipro.presentation.resume.dto.UpdateCertificationsRequest.CertificationRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.UpdateCertificationsUseCase;
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

@WebMvcTest(UpdateCertificationsController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class UpdateCertificationsControllerTest {

    @MockitoBean
    private UpdateCertificationsUseCase updateCertificationsUseCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;
    private final ObjectMapper objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());

    private static final String ENDPOINT = "/api/resumes/{resumeId}/certifications";
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final String RESUME_NAME = "職務経歴書テスト";
    private static final LocalDate DATE = LocalDate.of(2021, 5, 20);
    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2021, 5, 15, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2021, 5, 18, 15, 30);
    private static final DateTimeFormatter FMT = DateTimeFormatter.ISO_LOCAL_DATE_TIME;

    @Test
    @DisplayName("正常なリクエストの場合、200と更新後の職務経歴書情報が返る")
    void test1() throws Exception {
        // リクエスト作成
        CertificationRequest certReq = new CertificationRequest(
                null,
                "基本情報技術者試験",
                YearMonth.of(2020, 4));
        UpdateCertificationsRequest req = new UpdateCertificationsRequest(List.of(certReq));
        String body = objectMapper.writeValueAsString(req);

        // UseCaseDtoを生成
        ResumeInfoUseCaseDto dto = ResumeObjectBuilder.buildResumeInfoUseCaseDto(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        // モック設定
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(updateCertificationsUseCase.execute(eq(USER_ID), eq(RESUME_ID), any(UpdateCertificationsRequest.class)))
                .thenReturn(dto);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
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
                .andExpect(jsonPath("$.socialLinks.length()").value(1))
                .andExpect(jsonPath("$.selfPromotions.length()").value(1));

        verify(currentUserFacade).getUserId();
        verify(updateCertificationsUseCase).execute(eq(USER_ID), eq(RESUME_ID), any(UpdateCertificationsRequest.class));
    }

    @Test
    @DisplayName("資格名が空の場合、バリデーションエラーとなる")
    void test2() throws Exception {
        CertificationRequest certReq = new CertificationRequest(
                null,
                "",
                YearMonth.of(2020, 4));
        UpdateCertificationsRequest req = new UpdateCertificationsRequest(List.of(certReq));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors['certifications[0].name']").isArray())
                .andExpect(jsonPath("$.errors['certifications[0].name']",
                        hasItem("資格名は入力必須です。")));

        verify(updateCertificationsUseCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("資格名が50文字超の場合、バリデーションエラーとなる")
    void test3() throws Exception {
        String longName = "a".repeat(51);
        CertificationRequest certReq = new CertificationRequest(
                null,
                longName,
                YearMonth.of(2020, 4));
        UpdateCertificationsRequest req = new UpdateCertificationsRequest(List.of(certReq));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors['certifications[0].name']").isArray())
                .andExpect(jsonPath("$.errors['certifications[0].name']",
                        hasItem("資格名は50文字以内で入力してください。")));

        verify(updateCertificationsUseCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("取得年月がnullの場合、バリデーションエラーとなる")
    void test4() throws Exception {
        CertificationRequest certReq = new CertificationRequest(
                null,
                "基本情報技術者試験",
                null);
        UpdateCertificationsRequest req = new UpdateCertificationsRequest(List.of(certReq));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors['certifications[0].date']").isArray())
                .andExpect(jsonPath("$.errors['certifications[0].date']",
                        hasItem("取得年月は入力必須です。")));

        verify(updateCertificationsUseCase, never()).execute(any(), any(), any());
    }
}
