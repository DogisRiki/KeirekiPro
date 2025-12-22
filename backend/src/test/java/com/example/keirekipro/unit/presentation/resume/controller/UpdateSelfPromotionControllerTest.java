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
import java.time.format.DateTimeFormatter;
import java.util.UUID;

import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.presentation.resume.controller.UpdateSelfPromotionController;
import com.example.keirekipro.presentation.resume.dto.UpdateSelfPromotionRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.UpdateSelfPromotionUseCase;
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

@WebMvcTest(UpdateSelfPromotionController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class UpdateSelfPromotionControllerTest {

    @MockitoBean
    private UpdateSelfPromotionUseCase useCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;
    private final ObjectMapper objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());

    private static final String ENDPOINT = "/api/resumes/{resumeId}/self-promotions/{selfPromotionId}";
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID SELF_PROMOTION_ID = UUID.fromString("77777777-7777-7777-7777-777777777777");
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
        UpdateSelfPromotionRequest req = new UpdateSelfPromotionRequest(
                "自己PRタイトル",
                "自己PRコンテンツ");
        String body = objectMapper.writeValueAsString(req);

        // UseCaseDtoを生成
        ResumeInfoUseCaseDto dto = ResumeObjectBuilder.buildResumeInfoUseCaseDto(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        // モック設定
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(useCase.execute(eq(USER_ID), eq(RESUME_ID), eq(SELF_PROMOTION_ID),
                any(UpdateSelfPromotionRequest.class)))
                .thenReturn(dto);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, SELF_PROMOTION_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(RESUME_ID.toString()))
                .andExpect(jsonPath("$.resumeName").value(RESUME_NAME))
                .andExpect(jsonPath("$.date").value(DATE.toString()))
                .andExpect(jsonPath("$.createdAt").value(CREATED_AT.format(FMT)))
                .andExpect(jsonPath("$.updatedAt").value(UPDATED_AT.format(FMT)))
                .andExpect(jsonPath("$.lastName").value(LAST_NAME))
                .andExpect(jsonPath("$.firstName").value(FIRST_NAME))
                // ヘルパー実装どおり１件ずつ入っていることをチェック
                .andExpect(jsonPath("$.careers.length()").value(1))
                .andExpect(jsonPath("$.projects.length()").value(1))
                .andExpect(jsonPath("$.certifications.length()").value(1))
                .andExpect(jsonPath("$.portfolios.length()").value(1))
                .andExpect(jsonPath("$.snsPlatforms.length()").value(1))
                .andExpect(jsonPath("$.selfPromotions.length()").value(1));

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID), eq(RESUME_ID), eq(SELF_PROMOTION_ID),
                any(UpdateSelfPromotionRequest.class));
    }

    @Test
    @DisplayName("タイトルが空の場合、バリデーションエラーとなる")
    void test2() throws Exception {
        UpdateSelfPromotionRequest req = new UpdateSelfPromotionRequest(
                "",
                "自己PRコンテンツ");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, SELF_PROMOTION_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.title").isArray())
                .andExpect(jsonPath("$.errors.title",
                        hasItem("タイトルは入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("タイトルが50文字超の場合、バリデーションエラーとなる")
    void test3() throws Exception {
        UpdateSelfPromotionRequest req = new UpdateSelfPromotionRequest(
                "a".repeat(51),
                "自己PRコンテンツ");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, SELF_PROMOTION_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.title").isArray())
                .andExpect(jsonPath("$.errors.title",
                        hasItem("タイトルは50文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("コンテンツが空の場合、バリデーションエラーとなる")
    void test4() throws Exception {
        UpdateSelfPromotionRequest req = new UpdateSelfPromotionRequest(
                "自己PRタイトル",
                "");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, SELF_PROMOTION_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.content").isArray())
                .andExpect(jsonPath("$.errors.content",
                        hasItem("コンテンツは入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }

    @Test
    @DisplayName("コンテンツが1000文字超の場合、バリデーションエラーとなる")
    void test5() throws Exception {
        UpdateSelfPromotionRequest req = new UpdateSelfPromotionRequest(
                "自己PRタイトル",
                "a".repeat(1001));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID, SELF_PROMOTION_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.content").isArray())
                .andExpect(jsonPath("$.errors.content",
                        hasItem("コンテンツは1000文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any(), any());
    }
}
