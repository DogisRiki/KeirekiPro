package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeExportRuleCheckService;
import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.usecase.resume.ExportResumeUseCase;
import com.example.keirekipro.usecase.resume.command.ExportResumeCommand;
import com.example.keirekipro.usecase.resume.dto.ExportResumeUseCaseDto;
import com.example.keirekipro.usecase.resume.export.ExportFormat;
import com.example.keirekipro.usecase.resume.export.ExportedFile;
import com.example.keirekipro.usecase.resume.export.ResumeMarkdownExporter;
import com.example.keirekipro.usecase.resume.export.ResumePdfExportSettings;
import com.example.keirekipro.usecase.resume.export.ResumePdfExporter;
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
    private ResumePdfExporter pdfExporter;

    @Mock
    private ResumeMarkdownExporter markdownExporter;

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

        byte[] pdfContent = "PDF content".getBytes(StandardCharsets.UTF_8);
        ExportedFile exportedFile = new ExportedFile("dummy.pdf", "application/pdf", pdfContent);

        when(resumeRepository.find(RESUME_ID)).thenReturn(Optional.of(resume));
        when(resumeExportRuleCheckService.execute(resume)).thenReturn(List.of());
        when(pdfExporter.export(resume, ResumePdfExportSettings.defaults())).thenReturn(exportedFile);

        ExportResumeUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID.toString(), command(ExportFormat.PDF));

        verify(resumeRepository).find(RESUME_ID);
        verify(resumeExportRuleCheckService).execute(resume);
        verify(pdfExporter).export(resume, ResumePdfExportSettings.defaults());
        verify(markdownExporter, never()).export(any());

        assertThat(actual.getFileName()).isEqualTo("職務経歴書1.pdf");
        assertThat(actual.getContentType()).isEqualTo("application/pdf");
        assertThat(actual.getContent()).isEqualTo(pdfContent);
    }

    @Test
    @DisplayName("Markdown形式でエクスポートできる")
    void test2() {
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        byte[] mdContent = "# Markdown content".getBytes(StandardCharsets.UTF_8);
        ExportedFile exportedFile = new ExportedFile("dummy.md", "text/markdown", mdContent);

        when(resumeRepository.find(RESUME_ID)).thenReturn(Optional.of(resume));
        when(resumeExportRuleCheckService.execute(resume)).thenReturn(List.of());
        when(markdownExporter.export(resume)).thenReturn(exportedFile);

        ExportResumeUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID.toString(), command(ExportFormat.MARKDOWN));

        verify(resumeRepository).find(RESUME_ID);
        verify(resumeExportRuleCheckService).execute(resume);
        verify(markdownExporter).export(resume);
        verify(pdfExporter, never()).export(any(), any());

        assertThat(actual.getFileName()).isEqualTo("職務経歴書1.md");
        assertThat(actual.getContentType()).isEqualTo("text/markdown");
        assertThat(actual.getContent()).isEqualTo(mdContent);
    }

    @Test
    @DisplayName("対象の職務経歴書が存在しない場合、UseCaseExceptionがスローされる")
    void test3() {
        when(resumeRepository.find(RESUME_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID.toString(), command(ExportFormat.PDF)))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("対象の職務経歴書データが存在しません。");

        verify(resumeRepository).find(RESUME_ID);
        verify(resumeExportRuleCheckService, never()).execute(any());
        verify(pdfExporter, never()).export(any(), any());
        verify(markdownExporter, never()).export(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書をエクスポートしようとした場合、UseCaseExceptionがスローされる")
    void test4() {
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, OTHER_USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        when(resumeRepository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID.toString(), command(ExportFormat.PDF)))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("対象の職務経歴書データが存在しません。");

        verify(resumeRepository).find(RESUME_ID);
        verify(resumeExportRuleCheckService, never()).execute(any());
        verify(pdfExporter, never()).export(any(), any());
        verify(markdownExporter, never()).export(any());
    }

    @Test
    @DisplayName("エクスポート前提条件を満たさない場合、UseCaseExceptionがスローされる")
    void test5() {
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        when(resumeRepository.find(RESUME_ID)).thenReturn(Optional.of(resume));
        when(resumeExportRuleCheckService.execute(resume)).thenReturn(List.of("職歴を1件以上登録してください。"));

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID.toString(), command(ExportFormat.PDF)))
                .isInstanceOf(UseCaseException.class)
                .hasMessageContaining("職務経歴書をエクスポートできません。");

        verify(resumeRepository).find(RESUME_ID);
        verify(resumeExportRuleCheckService).execute(resume);
        verify(pdfExporter, never()).export(any(), any());
        verify(markdownExporter, never()).export(any());
    }

    @Test
    @DisplayName("PDFプレビュー時はPDF設定を補正してPDFエクスポートへ渡す")
    void test6() {
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        byte[] pdfContent = "PDF content".getBytes(StandardCharsets.UTF_8);
        ExportedFile exportedFile = new ExportedFile("dummy.pdf", "application/pdf", pdfContent);
        ExportResumeCommand command = new ExportResumeCommand(
                ExportFormat.PDF,
                ExportResumeCommand.ExportDisposition.INLINE,
                new ExportResumeCommand.PdfSettings(
                        "NotoSerifJP",
                        BigDecimal.valueOf(16),
                        BigDecimal.valueOf(10.2),
                        BigDecimal.valueOf(10.8),
                        BigDecimal.valueOf(11.4),
                        "#d9d9d9"));
        ResumePdfExportSettings expectedSettings = new ResumePdfExportSettings(
                "Noto Serif JP",
                BigDecimal.valueOf(16),
                BigDecimal.valueOf(10),
                BigDecimal.valueOf(11),
                BigDecimal.valueOf(11.5),
                "#d9d9d9");

        when(resumeRepository.find(RESUME_ID)).thenReturn(Optional.of(resume));
        when(resumeExportRuleCheckService.execute(resume)).thenReturn(List.of());
        when(pdfExporter.export(resume, expectedSettings)).thenReturn(exportedFile);

        ExportResumeUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID.toString(), command);

        verify(pdfExporter).export(resume, expectedSettings);
        assertThat(actual.getContent()).isEqualTo(pdfContent);
    }

    @Test
    @DisplayName("PDFプレビュー時にエクスポート前提条件を満たさない場合、プレビュー用メッセージでUseCaseExceptionがスローされる")
    void test7() {
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);
        ExportResumeCommand command = new ExportResumeCommand(
                ExportFormat.PDF,
                ExportResumeCommand.ExportDisposition.INLINE,
                new ExportResumeCommand.PdfSettings(
                        "NotoSansJP",
                        BigDecimal.valueOf(16),
                        BigDecimal.valueOf(10),
                        BigDecimal.valueOf(10),
                        BigDecimal.valueOf(11.5),
                        "#d9d9d9"));

        when(resumeRepository.find(RESUME_ID)).thenReturn(Optional.of(resume));
        when(resumeExportRuleCheckService.execute(resume)).thenReturn(List.of("自己PRを1件以上登録してください。"));

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID.toString(), command))
                .isInstanceOf(UseCaseException.class)
                .hasMessageContaining("入力エラーがあるため、PDFプレビューを表示できません。");

        verify(pdfExporter, never()).export(any(), any());
    }

    private static ExportResumeCommand command(ExportFormat format) {
        return new ExportResumeCommand(
                format,
                ExportResumeCommand.ExportDisposition.ATTACHMENT,
                null);
    }

}
