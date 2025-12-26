package com.example.keirekipro.infrastructure.shared.pdf;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;

import com.openhtmltopdf.pdfboxout.PdfRendererBuilder;

import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * openhtmltopdf（pdfboxout）を用いてHTMLをPDFへ変換する実装
 */
@Component
@RequiredArgsConstructor
public class OpenHtmlToPdfRenderer implements HtmlToPdfRenderer {

    private final ResourceLoader resourceLoader;

    /**
     * HTMLをPDFに変換する
     *
     * @param html HTML文字列
     * @return PDFバイト列
     */
    @Override
    public byte[] render(String html) {
        try (ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            PdfRendererBuilder builder = new PdfRendererBuilder();
            builder.withHtmlContent(html, null);

            // 日本語フォントを埋め込み登録する（実体に合わせてNORMALで登録）
            builder.useFont(
                    () -> openClasspath("classpath:/fonts/NotoSansJP-Regular.ttf"),
                    "Noto Sans JP",
                    400,
                    PdfRendererBuilder.FontStyle.NORMAL,
                    true);

            builder.useFont(
                    () -> openClasspath("classpath:/fonts/NotoSansJP-Bold.ttf"),
                    "Noto Sans JP",
                    700,
                    PdfRendererBuilder.FontStyle.NORMAL,
                    true);

            builder.toStream(out);
            builder.useFastMode();
            builder.run();
            return out.toByteArray();
        } catch (Exception e) {
            throw new IllegalStateException("PDF生成に失敗しました。", e);
        }
    }

    private InputStream openClasspath(String location) {
        try {
            return resourceLoader.getResource(location).getInputStream();
        } catch (Exception e) {
            throw new IllegalStateException("フォントの読み込みに失敗しました: " + location, e);
        }
    }
}
