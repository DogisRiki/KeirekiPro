package com.example.keirekipro.infrastructure.export.resume;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.infrastructure.shared.pdf.HtmlToPdfRenderer;
import com.example.keirekipro.usecase.resume.export.ExportedFile;
import com.example.keirekipro.usecase.resume.export.ResumePdfExportSettings;
import com.example.keirekipro.usecase.resume.export.ResumePdfExporter;

import org.springframework.stereotype.Component;
import org.thymeleaf.TemplateEngine;
import org.thymeleaf.context.Context;

import lombok.RequiredArgsConstructor;

/**
 * thymeleafでHTMLテンプレートをレンダリングしpdfbox系でPDF化して返すPDFエクスポート実装
 */
@Component("thymeleafResumePdfExporter")
@RequiredArgsConstructor
public class ThymeleafResumePdfExporter implements ResumePdfExporter {

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
    public ExportedFile export(Resume resume, ResumePdfExportSettings settings) {
        // テンプレートに渡すモデルを構築する
        Context context = new Context();
        context.setVariable("export", exportModelBuilder.build(resume));
        context.setVariable("pdfSettings", settings);

        // HTMLテンプレートをレンダリングする
        String html = templateEngine.process(TEMPLATE_NAME, context);

        // HTMLをPDFへ変換する
        byte[] pdf = htmlToPdfRenderer.render(html);

        return new ExportedFile(resume.getName().getValue() + ".pdf", CONTENT_TYPE, pdf);
    }
}
