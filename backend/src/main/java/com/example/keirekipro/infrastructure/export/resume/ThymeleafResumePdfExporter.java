package com.example.keirekipro.infrastructure.export.resume;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.infrastructure.shared.pdf.HtmlToPdfRenderer;
import com.example.keirekipro.usecase.resume.export.ExportedFile;
import com.example.keirekipro.usecase.resume.export.ResumeExporter;

import org.springframework.stereotype.Component;
import org.thymeleaf.TemplateEngine;
import org.thymeleaf.context.Context;

import lombok.RequiredArgsConstructor;

/**
 * thymeleafでHTMLテンプレートをレンダリングしpdfbox系でPDF化して返すResumeExporter実装
 */
@Component("thymeleafResumePdfExporter")
@RequiredArgsConstructor
public class ThymeleafResumePdfExporter implements ResumeExporter {

    private static final String CONTENT_TYPE = "application/pdf";
    private static final String TEMPLATE_NAME = "resume/pdf/simple";

    private final TemplateEngine templateEngine;
    private final ResumeExportModelBuilder exportModelBuilder;
    private final HtmlToPdfRenderer htmlToPdfRenderer;

    /**
     * 職務経歴書をPDFとしてエクスポートする
     *
     * @param resume 職務経歴書エンティティ
     * @return エクスポートしたファイル情報
     */
    @Override
    public ExportedFile exportPdf(Resume resume) {
        // テンプレートに渡すモデルを構築する
        Context context = new Context();
        context.setVariable("export", exportModelBuilder.build(resume));

        // HTMLテンプレートをレンダリングする
        String html = templateEngine.process(TEMPLATE_NAME, context);

        // HTMLをPDFへ変換する
        byte[] pdf = htmlToPdfRenderer.render(html);

        return new ExportedFile(resume.getName().getValue() + ".pdf", CONTENT_TYPE, pdf);
    }

    /**
     * Markdownエクスポートは対象外
     *
     * @param resume 職務経歴書エンティティ
     * @return 常にUnsupportedOperationExceptionをスロー
     */
    @Override
    public ExportedFile exportMarkdown(Resume resume) {
        throw new UnsupportedOperationException("Markdownエクスポートは対象外です。");
    }
}
