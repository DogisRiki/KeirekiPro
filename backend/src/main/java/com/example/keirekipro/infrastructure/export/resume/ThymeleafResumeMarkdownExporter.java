package com.example.keirekipro.infrastructure.export.resume;

import java.nio.charset.StandardCharsets;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.usecase.resume.export.ExportedFile;
import com.example.keirekipro.usecase.resume.export.ResumeExporter;

import org.springframework.stereotype.Component;
import org.thymeleaf.TemplateEngine;
import org.thymeleaf.context.Context;

import lombok.RequiredArgsConstructor;

/**
 * thymeleafでMarkdownテンプレートをレンダリングして返すResumeExporter実装
 */
@Component("thymeleafResumeMarkdownExporter")
@RequiredArgsConstructor
public class ThymeleafResumeMarkdownExporter implements ResumeExporter {

    private static final String CONTENT_TYPE = "text/markdown; charset=utf-8";
    private static final String TEMPLATE_NAME = "resume/markdown/default";

    private final TemplateEngine templateEngine;
    private final ResumeExportModelBuilder exportModelBuilder;

    /**
     * 職務経歴書をMarkdownとしてエクスポートする
     *
     * @param resume 職務経歴書エンティティ
     * @return エクスポートしたファイル情報
     */
    @Override
    public ExportedFile exportMarkdown(Resume resume) {
        // テンプレートに渡すモデルを構築する
        Context context = new Context();
        context.setVariable("export", exportModelBuilder.build(resume));

        // Markdownテンプレートをレンダリングし、UTF-8のバイト列として返す
        String markdown = templateEngine.process(TEMPLATE_NAME, context);
        byte[] content = markdown.getBytes(StandardCharsets.UTF_8);

        return new ExportedFile(resume.getName().getValue() + ".md", CONTENT_TYPE, content);
    }

    /**
     * PDFエクスポートは対象外
     *
     * @param resume 職務経歴書エンティティ
     * @return 常にUnsupportedOperationExceptionをスロー
     */
    @Override
    public ExportedFile exportPdf(Resume resume) {
        throw new UnsupportedOperationException("PDFエクスポートは対象外です。");
    }
}
