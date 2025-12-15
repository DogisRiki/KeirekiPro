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
import java.util.UUID;

import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.presentation.resume.controller.CreateCertificationController;
import com.example.keirekipro.presentation.resume.dto.CreateCertificationRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.CreateCertificationUseCase;
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

@WebMvcTest(CreateCertificationController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class CreateCertificationControllerTest {

    @MockitoBean
    private CreateCertificationUseCase createCertificationUseCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;
    private final ObjectMapper objectMapper = new ObjectMapper().findAndRegisterModules();

    private static final String ENDPOINT = "/api/resumes/{resumeId}/certifications";
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

    private static CreateCertificationRequest buildValidRequest() {
        return new CreateCertificationRequest("基本情報技術者試験", YearMonth.of(2020, 10));
    }

    @Test
    @DisplayName("正常なリクエストの場合、201と職務経歴書情報がレスポンスとして返る")
    void test1() throws Exception {
        CreateCertificationRequest req = buildValidRequest();
        String body = objectMapper.writeValueAsString(req);

        ResumeInfoUseCaseDto dto = ResumeObjectBuilder.buildResumeInfoUseCaseDto(
                RESUME_DTO_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(createCertificationUseCase.execute(eq(USER_ID), eq(RESUME_ID), any(CreateCertificationRequest.class)))
                .thenReturn(dto);

        mockMvc.perform(post(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(dto.getId().toString()))
                .andExpect(jsonPath("$.createdAt").value(CREATED_AT.format(FMT)))
                .andExpect(jsonPath("$.updatedAt").value(UPDATED_AT.format(FMT)));

        verify(currentUserFacade).getUserId();
        verify(createCertificationUseCase).execute(eq(USER_ID), eq(RESUME_ID), any(CreateCertificationRequest.class));
    }

    @Test
    @DisplayName("資格名が空の場合、バリデーションエラーとなる")
    void test2() throws Exception {
        CreateCertificationRequest req = buildValidRequest();
        req.setName("");
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.name").isArray())
                .andExpect(jsonPath("$.errors.name", hasItem("資格名は入力必須です。")));

        verify(createCertificationUseCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("資格名が50文字超の場合、バリデーションエラーとなる")
    void test3() throws Exception {
        CreateCertificationRequest req = buildValidRequest();
        req.setName("a".repeat(51));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.name").isArray())
                .andExpect(jsonPath("$.errors.name", hasItem("資格名は50文字以内で入力してください。")));

        verify(createCertificationUseCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("取得年月がnullの場合、バリデーションエラーとなる")
    void test4() throws Exception {
        CreateCertificationRequest req = buildValidRequest();
        req.setDate(null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.date").isArray())
                .andExpect(jsonPath("$.errors.date", hasItem("取得年月は入力必須です。")));

        verify(createCertificationUseCase, never()).execute(any(), any(), any());
    }
}
