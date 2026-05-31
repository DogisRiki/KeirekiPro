package com.example.keirekipro.unit.presentation.resume.controller;

import static org.hamcrest.Matchers.startsWith;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.UUID;

import com.example.keirekipro.presentation.resume.controller.ExportResumeController;
import com.example.keirekipro.presentation.resume.controller.ExportResumeWithSettingsController;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.ExportResumeUseCase;
import com.example.keirekipro.usecase.resume.command.ExportResumeCommand;
import com.example.keirekipro.usecase.resume.command.ExportResumeCommand.ExportDisposition;
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

@WebMvcTest({ ExportResumeController.class, ExportResumeWithSettingsController.class })
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

    private static ExportResumeCommand command(ExportFormat format, ExportDisposition disposition) {
        return new ExportResumeCommand(format, disposition, null);
    }

    @Test
    @DisplayName("Accept: application/pdfの場合、PDFファイルがダウンロードできる")
    void test1() throws Exception {
        byte[] pdfContent = "PDF content".getBytes(StandardCharsets.UTF_8);
        ExportResumeUseCaseDto dto = new ExportResumeUseCaseDto(
                "職務経歴書.pdf",
                "application/pdf",
                pdfContent);

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(useCase.execute(eq(USER_ID), eq(RESUME_ID.toString()),
                eq(command(ExportFormat.PDF, ExportDisposition.ATTACHMENT))))
                .thenReturn(dto);

        mockMvc.perform(get(ENDPOINT, RESUME_ID)
                .header(HttpHeaders.ACCEPT, MediaType.APPLICATION_PDF_VALUE))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_PDF))
                .andExpect(header().exists(HttpHeaders.CONTENT_DISPOSITION))
                .andExpect(content().bytes(pdfContent));

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID), eq(RESUME_ID.toString()),
                eq(command(ExportFormat.PDF, ExportDisposition.ATTACHMENT)));
    }

    @Test
    @DisplayName("Accept: text/markdownの場合、Markdownファイルがダウンロードできる")
    void test2() throws Exception {
        byte[] mdContent = "# Markdown content".getBytes(StandardCharsets.UTF_8);
        ExportResumeUseCaseDto dto = new ExportResumeUseCaseDto(
                "職務経歴書.md",
                "text/markdown",
                mdContent);

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        when(useCase.execute(eq(USER_ID), eq(RESUME_ID.toString()),
                eq(command(ExportFormat.MARKDOWN, ExportDisposition.ATTACHMENT))))
                .thenReturn(dto);

        mockMvc.perform(get(ENDPOINT, RESUME_ID)
                .header(HttpHeaders.ACCEPT, "text/markdown"))
                .andExpect(status().isOk())
                .andExpect(content().contentType("text/markdown"))
                .andExpect(header().exists(HttpHeaders.CONTENT_DISPOSITION))
                .andExpect(content().bytes(mdContent));

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID), eq(RESUME_ID.toString()),
                eq(command(ExportFormat.MARKDOWN, ExportDisposition.ATTACHMENT)));
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

    @Test
    @DisplayName("POSTでPDFプレビューを生成する場合、inlineのContent-DispositionでPDFを返す")
    void test5() throws Exception {
        byte[] pdfContent = "PDF content".getBytes(StandardCharsets.UTF_8);
        ExportResumeUseCaseDto dto = new ExportResumeUseCaseDto(
                "職務経歴書.pdf",
                "application/pdf",
                pdfContent);

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        ExportResumeCommand expectedCommand = new ExportResumeCommand(
                ExportFormat.PDF,
                ExportDisposition.INLINE,
                new ExportResumeCommand.PdfSettings(
                        "NotoSansJP",
                        new BigDecimal("16"),
                        new BigDecimal("10"),
                        new BigDecimal("10"),
                        new BigDecimal("11.5"),
                        "#d9d9d9"));
        when(useCase.execute(eq(USER_ID), eq(RESUME_ID.toString()), eq(expectedCommand))).thenReturn(dto);

        mockMvc.perform(post(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "format": "pdf",
                          "disposition": "inline",
                          "pdfSettings": {
                            "fontFamily": "NotoSansJP",
                            "fontSizes": {
                              "title": 16,
                              "date": 10,
                              "fullName": 10,
                              "sectionHeading": 11.5
                            },
                            "tableHeaderColor": {
                              "hex": "d9d9d9"
                            }
                          }
                        }
                        """))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_PDF))
                .andExpect(header().string(HttpHeaders.CONTENT_DISPOSITION, startsWith("inline")))
                .andExpect(content().bytes(pdfContent));

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID), eq(RESUME_ID.toString()), eq(expectedCommand));
    }

    @Test
    @DisplayName("POSTでPDFをダウンロードする場合、attachmentのContent-DispositionでPDFを返す")
    void test6() throws Exception {
        byte[] pdfContent = "PDF content".getBytes(StandardCharsets.UTF_8);
        ExportResumeUseCaseDto dto = new ExportResumeUseCaseDto(
                "職務経歴書.pdf",
                "application/pdf",
                pdfContent);

        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());
        ExportResumeCommand expectedCommand = new ExportResumeCommand(
                ExportFormat.PDF,
                ExportDisposition.ATTACHMENT,
                new ExportResumeCommand.PdfSettings(
                        "NotoSerifJP",
                        new BigDecimal("16"),
                        new BigDecimal("10"),
                        new BigDecimal("10"),
                        new BigDecimal("11.5"),
                        "#d9d9d9"));
        when(useCase.execute(eq(USER_ID), eq(RESUME_ID.toString()), eq(expectedCommand))).thenReturn(dto);

        mockMvc.perform(post(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "format": "pdf",
                          "disposition": "attachment",
                          "pdfSettings": {
                            "fontFamily": "NotoSerifJP",
                            "fontSizes": {
                              "title": 16,
                              "date": 10,
                              "fullName": 10,
                              "sectionHeading": 11.5
                            },
                            "tableHeaderColor": {
                              "rgb": { "r": 217, "g": 217, "b": 217 }
                            }
                          }
                        }
                        """))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_PDF))
                .andExpect(header().string(HttpHeaders.CONTENT_DISPOSITION, startsWith("attachment")))
                .andExpect(content().bytes(pdfContent));

        verify(currentUserFacade).getUserId();
        verify(useCase).execute(eq(USER_ID), eq(RESUME_ID.toString()), eq(expectedCommand));
    }

    @Test
    @DisplayName("POSTのPDF設定が不正な場合、400エラーとなる")
    void test7() throws Exception {
        mockMvc.perform(post(ENDPOINT, RESUME_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "format": "pdf",
                          "disposition": "inline",
                          "pdfSettings": {
                            "fontFamily": "Unknown",
                            "fontSizes": {
                              "title": 16,
                              "date": 10,
                              "fullName": 10,
                              "sectionHeading": 11.5
                            },
                            "tableHeaderColor": {
                              "hex": "d9d9d9"
                            }
                          }
                        }
                        """))
                .andExpect(status().isBadRequest());
    }
}
