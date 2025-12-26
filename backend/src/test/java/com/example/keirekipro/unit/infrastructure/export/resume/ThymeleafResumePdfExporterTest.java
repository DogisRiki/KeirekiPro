package com.example.keirekipro.unit.infrastructure.export.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.LinkedHashMap;
import java.util.Map;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.infrastructure.export.resume.ResumeExportModelBuilder;
import com.example.keirekipro.infrastructure.export.resume.ThymeleafResumePdfExporter;
import com.example.keirekipro.infrastructure.shared.pdf.HtmlToPdfRenderer;
import com.example.keirekipro.usecase.resume.export.ExportedFile;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.thymeleaf.TemplateEngine;
import org.thymeleaf.context.Context;

@ExtendWith(MockitoExtension.class)
class ThymeleafResumePdfExporterTest {

    @Mock
    private TemplateEngine templateEngine;

    @Mock
    private ResumeExportModelBuilder exportModelBuilder;

    @Mock
    private HtmlToPdfRenderer htmlToPdfRenderer;

    @Test
    @DisplayName("exportPdfメソッドでThymeleafレンダリング結果をPDFへ変換しExportedFileとして返す")
    void test1() {
        // Resume
        Resume resume = mock(Resume.class);
        ResumeName resumeName = mock(ResumeName.class);
        when(resumeName.getValue()).thenReturn("職務経歴書_テスト");
        when(resume.getName()).thenReturn(resumeName);

        // Export model
        Map<String, Object> model = new LinkedHashMap<>();
        model.put("title", "職務経歴書");
        when(exportModelBuilder.build(resume)).thenReturn(model);

        // Thymeleaf
        when(templateEngine.process(eq("resume/pdf/simple"), any(Context.class)))
                .thenReturn("<html>test</html>");

        // PDF renderer
        byte[] pdfBytes = "PDF".getBytes();
        when(htmlToPdfRenderer.render("<html>test</html>")).thenReturn(pdfBytes);

        // Contextキャプチャ
        ArgumentCaptor<Context> contextCaptor = ArgumentCaptor.forClass(Context.class);

        // 実行
        final ThymeleafResumePdfExporter exporter = new ThymeleafResumePdfExporter(
                templateEngine,
                exportModelBuilder,
                htmlToPdfRenderer);
        ExportedFile result = exporter.exportPdf(resume);

        // 検証（templateEngine呼び出し）
        verify(templateEngine).process(eq("resume/pdf/simple"), contextCaptor.capture());
        Context capturedContext = contextCaptor.getValue();
        assertThat(capturedContext.getVariable("export")).isEqualTo(model);

        // 検証（PDF変換呼び出し）
        verify(htmlToPdfRenderer).render("<html>test</html>");

        // 検証（戻り値）
        assertThat(result.getFileName()).isEqualTo("職務経歴書_テスト.pdf");
        assertThat(result.getContentType()).isEqualTo("application/pdf");
        assertThat(result.getContent()).isEqualTo(pdfBytes);
    }
}
