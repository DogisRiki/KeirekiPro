package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeExportRuleCheckService;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.usecase.resume.ExportResumeUseCase;
import com.example.keirekipro.usecase.resume.dto.ExportResumeUseCaseDto;
import com.example.keirekipro.usecase.resume.export.ExportFormat;
import com.example.keirekipro.usecase.resume.export.ExportedFile;
import com.example.keirekipro.usecase.resume.export.ResumeExporter;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ExportResumeUseCaseTest {

    @Mock
    private ResumeRepository resumeRepository;

    @Mock
    private ResumeExportRuleCheckService resumeExportRuleCheckService;

    @Mock
    private ResumeExporter pdfExporter;

    @Mock
    private ResumeExporter markdownExporter;

    private ExportResumeUseCase useCase;

    @BeforeEach
    void setUp() {
        useCase = new ExportResumeUseCase(
                resumeRepository,
                resumeExportRuleCheckService,
                pdfExporter,
                markdownExporter);
    }

    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID OTHER_USER_ID = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final String RESUME_NAME = "職務経歴書1";
    private static final LocalDate DATE = LocalDate.of(2021, 5, 20);
    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2021, 5, 15, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2021, 5, 18, 15, 30);

    @Test
    @DisplayName("PDF形式でエクスポートできる")
    void test1() {
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        byte[] pdfContent = "PDF content".getBytes();
        ExportedFile exportedFile = new ExportedFile("dummy.pdf", "application/pdf", pdfContent);

        when(resumeRepository.find(RESUME_ID)).thenReturn(Optional.of(resume));
        doNothing().when(resumeExportRuleCheckService).execute(resume);
        when(pdfExporter.exportPdf(resume)).thenReturn(exportedFile);

        ExportResumeUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID, ExportFormat.PDF);

        verify(resumeRepository).find(RESUME_ID);
        verify(resumeExportRuleCheckService).execute(resume);
        verify(pdfExporter).exportPdf(resume);
        verify(markdownExporter, never()).exportMarkdown(any());

        assertThat(actual.getFileName()).isEqualTo("職務経歴書1.pdf");
        assertThat(actual.getContentType()).isEqualTo("application/pdf");
        assertThat(actual.getContent()).isEqualTo(pdfContent);
    }

    @Test
    @DisplayName("Markdown形式でエクスポートできる")
    void test2() {
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        byte[] mdContent = "# Markdown content".getBytes();
        ExportedFile exportedFile = new ExportedFile("dummy.md", "text/markdown", mdContent);

        when(resumeRepository.find(RESUME_ID)).thenReturn(Optional.of(resume));
        doNothing().when(resumeExportRuleCheckService).execute(resume);
        when(markdownExporter.exportMarkdown(resume)).thenReturn(exportedFile);

        ExportResumeUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID, ExportFormat.MARKDOWN);

        verify(resumeRepository).find(RESUME_ID);
        verify(resumeExportRuleCheckService).execute(resume);
        verify(markdownExporter).exportMarkdown(resume);
        verify(pdfExporter, never()).exportPdf(any());

        assertThat(actual.getFileName()).isEqualTo("職務経歴書1.md");
        assertThat(actual.getContentType()).isEqualTo("text/markdown");
        assertThat(actual.getContent()).isEqualTo(mdContent);
    }

    @Test
    @DisplayName("対象の職務経歴書が存在しない場合、UseCaseExceptionがスローされる")
    void test3() {
        when(resumeRepository.find(RESUME_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, ExportFormat.PDF))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(resumeRepository).find(RESUME_ID);
        verify(resumeExportRuleCheckService, never()).execute(any());
        verify(pdfExporter, never()).exportPdf(any());
        verify(markdownExporter, never()).exportMarkdown(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書をエクスポートしようとした場合、UseCaseExceptionがスローされる")
    void test4() {
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, OTHER_USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        when(resumeRepository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, ExportFormat.PDF))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(resumeRepository).find(RESUME_ID);
        verify(resumeExportRuleCheckService, never()).execute(any());
        verify(pdfExporter, never()).exportPdf(any());
        verify(markdownExporter, never()).exportMarkdown(any());
    }

    @Test
    @DisplayName("エクスポート前提条件を満たさない場合、DomainExceptionがスローされる")
    void test5() {
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        when(resumeRepository.find(RESUME_ID)).thenReturn(Optional.of(resume));
        doThrow(new DomainException("職務経歴書をエクスポートできません。\n- 職歴を1件以上登録してください。"))
                .when(resumeExportRuleCheckService).execute(resume);

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, ExportFormat.PDF))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("職務経歴書をエクスポートできません。");

        verify(resumeRepository).find(RESUME_ID);
        verify(resumeExportRuleCheckService).execute(resume);
        verify(pdfExporter, never()).exportPdf(any());
        verify(markdownExporter, never()).exportMarkdown(any());
    }

}
