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
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.presentation.resume.controller.CreateResumeController;
import com.example.keirekipro.presentation.resume.dto.CreateResumeRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.CopyCreateResumeUseCase;
import com.example.keirekipro.usecase.resume.CreateResumeUseCase;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(CreateResumeController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class CreateResumeControllerTest {

    @MockitoBean
    private CreateResumeUseCase createResumeUseCase;

    @MockitoBean
    private CopyCreateResumeUseCase copyCreateResumeUseCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;
    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final String ENDPOINT = "/api/resumes";
    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID EXISTING_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final String RESUME_NAME = "職務経歴書テスト";
    private static final LocalDate DATE = LocalDate.of(2021, 5, 20);
    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2021, 5, 15, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2021, 5, 18, 15, 30);

    private static final DateTimeFormatter FMT = DateTimeFormatter.ISO_LOCAL_DATE_TIME;

    @Test
    @DisplayName("新規作成リクエストの場合、201と職務経歴書情報がレスポンスとして返る")
    void test1() throws Exception {
        // リクエスト作成
        CreateResumeRequest req = new CreateResumeRequest(RESUME_NAME, null);
        String body = objectMapper.writeValueAsString(req);

        // 新規作成用DTOを直接builderで組み立て
        ResumeInfoUseCaseDto dto = ResumeInfoUseCaseDto.builder()
                .id(EXISTING_ID)
                .resumeName(RESUME_NAME)
                .date(DATE)
                .lastName(LAST_NAME)
                .firstName(FIRST_NAME)
                .createdAt(CREATED_AT)
                .updatedAt(UPDATED_AT)
                .careers(List.of())
                .projects(List.of())
                .certifications(List.of())
                .portfolios(List.of())
                .snsPlatforms(List.of())
                .selfPromotions(List.of())
                .build();

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(createResumeUseCase.execute(eq(USER_ID), any(CreateResumeRequest.class))).thenReturn(dto);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(dto.getId().toString()))
                .andExpect(jsonPath("$.resumeName").value(RESUME_NAME))
                .andExpect(jsonPath("$.date").value(DATE.toString()))
                .andExpect(jsonPath("$.createdAt").value(CREATED_AT.format(FMT)))
                .andExpect(jsonPath("$.updatedAt").value(UPDATED_AT.format(FMT)))
                .andExpect(jsonPath("$.lastName").value(LAST_NAME))
                .andExpect(jsonPath("$.firstName").value(FIRST_NAME))
                // 以下は存在しない
                .andExpect(jsonPath("$.careers").doesNotExist())
                .andExpect(jsonPath("$.projects").doesNotExist())
                .andExpect(jsonPath("$.certifications").doesNotExist())
                .andExpect(jsonPath("$.portfolios").doesNotExist())
                .andExpect(jsonPath("$.snsPlatforms").doesNotExist())
                .andExpect(jsonPath("$.selfPromotions").doesNotExist());

        verify(currentUserFacade).getUserId();
        verify(createResumeUseCase).execute(eq(USER_ID), any(CreateResumeRequest.class));
        verify(copyCreateResumeUseCase, never()).execute(any(), any());
    }

    @Test
    @DisplayName("コピー作成リクエストの場合、201と完全な職務経歴書情報がレスポンスとして返る")
    void test2() throws Exception {
        // リクエスト作成
        CreateResumeRequest req = new CreateResumeRequest(RESUME_NAME, EXISTING_ID);
        String body = objectMapper.writeValueAsString(req);

        // ヘルパーでDTOを用意
        ResumeInfoUseCaseDto dto = ResumeObjectBuilder.buildResumeInfoUseCaseDto(
                EXISTING_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(copyCreateResumeUseCase.execute(eq(USER_ID), any(CreateResumeRequest.class))).thenReturn(dto);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(dto.getId().toString()))
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
        verify(copyCreateResumeUseCase).execute(eq(USER_ID), any(CreateResumeRequest.class));
        verify(createResumeUseCase, never()).execute(any(), any());
    }

    @Test
    @DisplayName("職務経歴書名が空の場合、バリデーションエラーとなる")
    void test3() throws Exception {
        CreateResumeRequest req = new CreateResumeRequest("", null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.resumeName").isArray())
                .andExpect(jsonPath("$.errors.resumeName", hasItem("職務経歴書名は入力必須です。")));

        verify(createResumeUseCase, never()).execute(any(), any());
        verify(copyCreateResumeUseCase, never()).execute(any(), any());
    }

    @Test
    @DisplayName("職務経歴書名が50文字超の場合、バリデーションエラーとなる")
    void test4() throws Exception {
        String longName = "a".repeat(51);
        CreateResumeRequest req = new CreateResumeRequest(longName, null);
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.resumeName").isArray())
                .andExpect(jsonPath("$.errors.resumeName", hasItem("職務経歴書名は50文字以内で入力してください。")));

        verify(createResumeUseCase, never()).execute(any(), any());
        verify(copyCreateResumeUseCase, never()).execute(any(), any());
    }
}
