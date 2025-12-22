package com.example.keirekipro.unit.presentation.resume.controller;

import static org.hamcrest.Matchers.hasItem;
import static org.junit.jupiter.api.Assertions.assertEquals;
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
import com.example.keirekipro.presentation.resume.controller.UpdateResumeBasicController;
import com.example.keirekipro.presentation.resume.dto.UpdateResumeBasicRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.UpdateResumeBasicUseCase;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestConstructor.AutowireMode;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(UpdateResumeBasicController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class UpdateResumeBasicControllerTest {

    @MockitoBean
    private UpdateResumeBasicUseCase useCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;
    private final ObjectMapper objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());

    private static final String ENDPOINT = "/api/resumes/{resumeId}/basic";
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
    @DisplayName("正常なリクエストの場合、200と更新後の職務経歴書情報が返り、全項目がユースケースに正しく引き渡される")
    void test1() throws Exception {
        // リクエスト作成
        UpdateResumeBasicRequest req = new UpdateResumeBasicRequest(
                RESUME_NAME,
                DATE,
                LAST_NAME,
                FIRST_NAME);
        String body = objectMapper.writeValueAsString(req);

        // UseCaseDtoを生成
        ResumeInfoUseCaseDto dto = ResumeObjectBuilder.buildResumeInfoUseCaseDto(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        // モック設定
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(useCase.execute(eq(USER_ID), eq(RESUME_ID), any(UpdateResumeBasicRequest.class)))
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
                .andExpect(jsonPath("$.lastName").value(LAST_NAME))
                .andExpect(jsonPath("$.firstName").value(FIRST_NAME))
                // ヘルパー実装どおり１件ずつ入っていることをチェック
                .andExpect(jsonPath("$.careers.length()").value(1))
                .andExpect(jsonPath("$.projects.length()").value(1))
                .andExpect(jsonPath("$.certifications.length()").value(1))
                .andExpect(jsonPath("$.portfolios.length()").value(1))
                .andExpect(jsonPath("$.snsPlatforms.length()").value(1))
                .andExpect(jsonPath("$.selfPromotions.length()").value(1));

        // ユースケースに渡されたリクエスト内容を検証
        ArgumentCaptor<UpdateResumeBasicRequest> captor = ArgumentCaptor.forClass(UpdateResumeBasicRequest.class);
        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID), eq(RESUME_ID), captor.capture());

        UpdateResumeBasicRequest actual = captor.getValue();
        assertEquals(req, actual);
    }

    @Test
    @DisplayName("職務経歴書名が空の場合、バリデーションエラーとなる")
    void test2() throws Exception {
        UpdateResumeBasicRequest req = new UpdateResumeBasicRequest(
                "",
                DATE,
                LAST_NAME,
                FIRST_NAME);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.resumeName").isArray())
                .andExpect(jsonPath("$.errors.resumeName",
                        hasItem("職務経歴書名は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("職務経歴書名が50文字超の場合、バリデーションエラーとなる")
    void test3() throws Exception {
        String longName = "a".repeat(51);
        UpdateResumeBasicRequest req = new UpdateResumeBasicRequest(
                longName,
                DATE,
                LAST_NAME,
                FIRST_NAME);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.resumeName").isArray())
                .andExpect(jsonPath("$.errors.resumeName",
                        hasItem("職務経歴書名は50文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("日付がnullの場合、バリデーションエラーとなる")
    void test4() throws Exception {
        UpdateResumeBasicRequest req = new UpdateResumeBasicRequest(
                RESUME_NAME,
                null,
                LAST_NAME,
                FIRST_NAME);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.date").isArray())
                .andExpect(jsonPath("$.errors.date",
                        hasItem("日付は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("姓が空の場合、バリデーションエラーとなる")
    void test5() throws Exception {
        UpdateResumeBasicRequest req = new UpdateResumeBasicRequest(
                RESUME_NAME,
                DATE,
                "",
                FIRST_NAME);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.lastName").isArray())
                .andExpect(jsonPath("$.errors.lastName",
                        hasItem("姓は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("姓が10文字超の場合、バリデーションエラーとなる")
    void test6() throws Exception {
        String longLastName = "あ".repeat(11);
        UpdateResumeBasicRequest req = new UpdateResumeBasicRequest(
                RESUME_NAME,
                DATE,
                longLastName,
                FIRST_NAME);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.lastName").isArray())
                .andExpect(jsonPath("$.errors.lastName",
                        hasItem("姓は10文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("名が空の場合、バリデーションエラーとなる")
    void test7() throws Exception {
        UpdateResumeBasicRequest req = new UpdateResumeBasicRequest(
                RESUME_NAME,
                DATE,
                LAST_NAME,
                "");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.firstName").isArray())
                .andExpect(jsonPath("$.errors.firstName",
                        hasItem("名は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("名が10文字超の場合、バリデーションエラーとなる")
    void test8() throws Exception {
        String longFirstName = "あ".repeat(11);
        UpdateResumeBasicRequest req = new UpdateResumeBasicRequest(
                RESUME_NAME,
                DATE,
                LAST_NAME,
                longFirstName);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.firstName").isArray())
                .andExpect(jsonPath("$.errors.firstName",
                        hasItem("名は10文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("日付の年が1900未満の場合、バリデーションエラーとなる")
    void test9() throws Exception {
        UpdateResumeBasicRequest req = new UpdateResumeBasicRequest(
                RESUME_NAME,
                LocalDate.of(1899, 12, 31),
                LAST_NAME,
                FIRST_NAME);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.date").isArray())
                .andExpect(jsonPath("$.errors.date", hasItem("日付が不正です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("日付の年が2100超の場合、バリデーションエラーとなる")
    void test10() throws Exception {
        UpdateResumeBasicRequest req = new UpdateResumeBasicRequest(
                RESUME_NAME,
                LocalDate.of(2101, 1, 1),
                LAST_NAME,
                FIRST_NAME);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.date").isArray())
                .andExpect(jsonPath("$.errors.date", hasItem("日付が不正です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }
}
