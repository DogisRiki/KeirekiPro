package com.example.keirekipro.unit.presentation.resume.controller;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.controller.ExportResumeController;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.ExportResumeUseCase;
import com.example.keirekipro.usecase.resume.dto.ExportResumeUseCaseDto;
import com.example.keirekipro.usecase.resume.export.ExportFormat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestConstructor.AutowireMode;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(ExportResumeController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = AutowireMode.ALL)
@RequiredArgsConstructor
class ExportResumeControllerTest {

    @MockitoBean
    private ExportResumeUseCase useCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/resumes/{resumeId}/export";
    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");

    @Test
    @DisplayName("Accept: application/pdfの場合、PDFファイルがダウンロードできる")
    void test1() throws Exception {
        byte[] pdfContent = "PDF content".getBytes();
        ExportResumeUseCaseDto dto = new ExportResumeUseCaseDto(
                "職務経歴書.pdf",
                "application/pdf",
                pdfContent);

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(useCase.execute(eq(USER_ID), eq(RESUME_ID), eq(ExportFormat.PDF))).thenReturn(dto);

        mockMvc.perform(get(ENDPOINT, RESUME_ID)
                .header(HttpHeaders.ACCEPT, MediaType.APPLICATION_PDF_VALUE))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_PDF))
                .andExpect(header().exists(HttpHeaders.CONTENT_DISPOSITION))
                .andExpect(content().bytes(pdfContent));

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID), eq(RESUME_ID), eq(ExportFormat.PDF));
    }

    @Test
    @DisplayName("Accept: text/markdownの場合、Markdownファイルがダウンロードできる")
    void test2() throws Exception {
        byte[] mdContent = "# Markdown content".getBytes();
        ExportResumeUseCaseDto dto = new ExportResumeUseCaseDto(
                "職務経歴書.md",
                "text/markdown",
                mdContent);

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(useCase.execute(eq(USER_ID), eq(RESUME_ID), eq(ExportFormat.MARKDOWN))).thenReturn(dto);

        mockMvc.perform(get(ENDPOINT, RESUME_ID)
                .header(HttpHeaders.ACCEPT, "text/markdown"))
                .andExpect(status().isOk())
                .andExpect(content().contentType("text/markdown"))
                .andExpect(header().exists(HttpHeaders.CONTENT_DISPOSITION))
                .andExpect(content().bytes(mdContent));

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID), eq(RESUME_ID), eq(ExportFormat.MARKDOWN));
    }

    @Test
    @DisplayName("Acceptヘッダーが想定外の場合、500エラーとなる")
    void test3() throws Exception {
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());

        mockMvc.perform(get(ENDPOINT, RESUME_ID)
                .header(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON_VALUE))
                .andExpect(status().isInternalServerError());

        verify(currentUserFacade).getUserId();
    }

    @Test
    @DisplayName("Acceptヘッダーがない場合、500エラーとなる")
    void test4() throws Exception {
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());

        mockMvc.perform(get(ENDPOINT, RESUME_ID))
                .andExpect(status().isInternalServerError());

        verify(currentUserFacade).getUserId();
    }
}
