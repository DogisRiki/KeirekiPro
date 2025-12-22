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
import java.time.format.DateTimeFormatter;
import java.util.UUID;

import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.presentation.resume.controller.CreateSnsPlatformController;
import com.example.keirekipro.presentation.resume.dto.CreateSnsPlatformRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.CreateSnsPlatformUseCase;
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

@WebMvcTest(CreateSnsPlatformController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class CreateSnsPlatformControllerTest {

    @MockitoBean
    private CreateSnsPlatformUseCase useCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;
    private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

    private static final String ENDPOINT = "/api/resumes/{resumeId}/sns-platforms";
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

    private static CreateSnsPlatformRequest buildValidRequest() {
        return new CreateSnsPlatformRequest("GitHub", "https://example.com/github");
    }

    @Test
    @DisplayName("正常なリクエストの場合、201と職務経歴書情報がレスポンスとして返る")
    void test1() throws Exception {
        CreateSnsPlatformRequest req = buildValidRequest();
        String body = objectMapper.writeValueAsString(req);

        ResumeInfoUseCaseDto dto = ResumeObjectBuilder.buildResumeInfoUseCaseDto(
                RESUME_DTO_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(useCase.execute(eq(USER_ID), eq(RESUME_ID), any(CreateSnsPlatformRequest.class)))
                .thenReturn(dto);

        mockMvc.perform(post(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(dto.getId().toString()))
                .andExpect(jsonPath("$.createdAt").value(CREATED_AT.format(FMT)))
                .andExpect(jsonPath("$.updatedAt").value(UPDATED_AT.format(FMT)));

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID), eq(RESUME_ID), any(CreateSnsPlatformRequest.class));
    }

    @Test
    @DisplayName("プラットフォーム名が空の場合、バリデーションエラーとなる")
    void test2() throws Exception {
        CreateSnsPlatformRequest req = buildValidRequest();
        req.setName("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.name").isArray())
                .andExpect(jsonPath("$.errors.name", hasItem("プラットフォーム名は入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("プラットフォーム名が50文字超の場合、バリデーションエラーとなる")
    void test3() throws Exception {
        CreateSnsPlatformRequest req = buildValidRequest();
        req.setName("a".repeat(51));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.name").isArray())
                .andExpect(jsonPath("$.errors.name", hasItem("プラットフォーム名は50文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("リンクが空の場合、バリデーションエラーとなる")
    void test4() throws Exception {
        CreateSnsPlatformRequest req = buildValidRequest();
        req.setLink("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.link").isArray())
                .andExpect(jsonPath("$.errors.link", hasItem("リンクは入力必須です。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("リンクがhttps形式でない場合、バリデーションエラーとなる")
    void test5() throws Exception {
        CreateSnsPlatformRequest req = buildValidRequest();
        req.setLink("http://example.com/github");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.link").isArray())
                .andExpect(jsonPath("$.errors.link", hasItem("リンクはhttps形式のURLを指定してください。")));

        verify(useCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("リンクが255文字超の場合、バリデーションエラーとなる")
    void test6() throws Exception {
        CreateSnsPlatformRequest req = buildValidRequest();
        req.setLink("https://example.com/" + "a".repeat(300));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.link").isArray())
                .andExpect(jsonPath("$.errors.link", hasItem("リンクは255文字以内で入力してください。")));

        verify(useCase, never()).execute(any(), any(), any());
    }
}
