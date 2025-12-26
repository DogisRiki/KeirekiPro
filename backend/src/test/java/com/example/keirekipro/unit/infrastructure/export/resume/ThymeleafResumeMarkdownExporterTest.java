package com.example.keirekipro.unit.infrastructure.export.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.infrastructure.export.resume.ResumeExportModelBuilder;
import com.example.keirekipro.infrastructure.export.resume.ThymeleafResumeMarkdownExporter;
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
class ThymeleafResumeMarkdownExporterTest {

    @Mock
    private TemplateEngine templateEngine;

    @Mock
    private ResumeExportModelBuilder exportModelBuilder;

    @Test
    @DisplayName("exportMarkdownメソッドでThymeleafレンダリング結果をUTF-8バイト列としてExportedFileで返す")
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
        String markdown = "# test\n";
        when(templateEngine.process(eq("resume/markdown/default"), any(Context.class)))
                .thenReturn(markdown);

        // Contextキャプチャ
        ArgumentCaptor<Context> contextCaptor = ArgumentCaptor.forClass(Context.class);

        // 実行
        final ThymeleafResumeMarkdownExporter exporter = new ThymeleafResumeMarkdownExporter(
                templateEngine,
                exportModelBuilder);
        ExportedFile result = exporter.exportMarkdown(resume);

        // 検証（templateEngine呼び出し）
        verify(templateEngine).process(eq("resume/markdown/default"), contextCaptor.capture());
        Context capturedContext = contextCaptor.getValue();
        assertThat(capturedContext.getVariable("export")).isEqualTo(model);

        // 検証（戻り値）
        assertThat(result.getFileName()).isEqualTo("職務経歴書_テスト.md");
        assertThat(result.getContentType()).isEqualTo("text/markdown; charset=utf-8");
        assertThat(new String(result.getContent(), StandardCharsets.UTF_8)).isEqualTo(markdown);
    }
}
