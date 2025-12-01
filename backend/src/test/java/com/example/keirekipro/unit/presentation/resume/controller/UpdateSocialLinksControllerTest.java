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
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.presentation.resume.controller.UpdateSocialLinksController;
import com.example.keirekipro.presentation.resume.dto.UpdateSocialLinksRequest;
import com.example.keirekipro.presentation.resume.dto.UpdateSocialLinksRequest.SocialLinkRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.UpdateSocialLinksUseCase;
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

@WebMvcTest(UpdateSocialLinksController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class UpdateSocialLinksControllerTest {

    @MockitoBean
    private UpdateSocialLinksUseCase updateSocialLinksUseCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;
    private final ObjectMapper objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());

    private static final String ENDPOINT = "/api/resumes/{resumeId}/social-links";
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final String RESUME_NAME = "職務経歴書テスト";
    private static final LocalDate DATE = LocalDate.of(2021, 5, 20);
    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2021, 5, 15, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2021, 5, 18, 15, 30);
    private static final DateTimeFormatter FMT = DateTimeFormatter.ISO_LOCAL_DATE_TIME;

    private SocialLinkRequest createValidSocialLinkRequest() {
        return new SocialLinkRequest(
                null,
                "GitHub",
                "https://github.com/example");
    }

    @Test
    @DisplayName("正常なリクエストの場合、200と更新後の職務経歴書情報が返り、全項目がユースケースに正しく引き渡される")
    void test1() throws Exception {
        // リクエスト作成
        SocialLinkRequest socialReq = createValidSocialLinkRequest();
        UpdateSocialLinksRequest req = new UpdateSocialLinksRequest(List.of(socialReq));
        String body = objectMapper.writeValueAsString(req);

        // UseCaseDtoを生成
        ResumeInfoUseCaseDto dto = ResumeObjectBuilder.buildResumeInfoUseCaseDto(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        // モック設定
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(updateSocialLinksUseCase.execute(eq(USER_ID), eq(RESUME_ID), any(UpdateSocialLinksRequest.class)))
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
                .andExpect(jsonPath("$.socialLinks.length()").value(1))
                .andExpect(jsonPath("$.selfPromotions.length()").value(1));

        // ユースケースに渡されたリクエスト内容を検証
        ArgumentCaptor<UpdateSocialLinksRequest> captor = ArgumentCaptor.forClass(UpdateSocialLinksRequest.class);
        verify(currentUserFacade).getUserId();
        verify(updateSocialLinksUseCase).execute(eq(USER_ID), eq(RESUME_ID), captor.capture());

        UpdateSocialLinksRequest actual = captor.getValue();
        assertEquals(req, actual);
    }

    @Test
    @DisplayName("ソーシャル名が空の場合、バリデーションエラーとなる")
    void test2() throws Exception {
        SocialLinkRequest socialReq = createValidSocialLinkRequest();
        socialReq.setName("");
        UpdateSocialLinksRequest req = new UpdateSocialLinksRequest(List.of(socialReq));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors['socialLinks[0].name']").isArray())
                .andExpect(jsonPath("$.errors['socialLinks[0].name']",
                        hasItem("ソーシャル名は入力必須です。")));

        verify(updateSocialLinksUseCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("ソーシャル名が50文字超の場合、バリデーションエラーとなる")
    void test3() throws Exception {
        SocialLinkRequest socialReq = createValidSocialLinkRequest();
        socialReq.setName("a".repeat(51));
        UpdateSocialLinksRequest req = new UpdateSocialLinksRequest(List.of(socialReq));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors['socialLinks[0].name']").isArray())
                .andExpect(jsonPath("$.errors['socialLinks[0].name']",
                        hasItem("ソーシャル名は50文字以内で入力してください。")));

        verify(updateSocialLinksUseCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("リンクが空の場合、バリデーションエラーとなる")
    void test4() throws Exception {
        SocialLinkRequest socialReq = createValidSocialLinkRequest();
        socialReq.setLink("");
        UpdateSocialLinksRequest req = new UpdateSocialLinksRequest(List.of(socialReq));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors['socialLinks[0].link']").isArray())
                .andExpect(jsonPath("$.errors['socialLinks[0].link']",
                        hasItem("リンクは入力必須です。")));

        verify(updateSocialLinksUseCase, never()).execute(any(), any(), any());
    }

    @Test
    @DisplayName("リンクがhttps形式以外の場合、バリデーションエラーとなる")
    void test5() throws Exception {
        SocialLinkRequest socialReq = createValidSocialLinkRequest();
        socialReq.setLink("http://example.com");
        UpdateSocialLinksRequest req = new UpdateSocialLinksRequest(List.of(socialReq));
        String body = objectMapper.writeValueAsString(req);

        mockMvc.perform(put(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors['socialLinks[0].link']").isArray())
                .andExpect(jsonPath("$.errors['socialLinks[0].link']",
                        hasItem("リンクはhttps形式のURLを指定してください。")));

        verify(updateSocialLinksUseCase, never()).execute(any(), any(), any());
    }
}
