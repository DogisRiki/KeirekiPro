package com.example.keirekipro.usecase.resume.dto;

import java.math.BigDecimal;

import com.example.keirekipro.usecase.resume.export.ExportFormat;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書エクスポートコマンド
 */
@Getter
@RequiredArgsConstructor
public class ExportResumeCommand {

    private final ExportFormat format;

    private final ExportDisposition disposition;

    private final PdfSettings pdfSettings;

    /**
     * PDFプレビューかどうか
     */
    public boolean isPreview() {
        return disposition == ExportDisposition.INLINE;
    }

    /**
     * エクスポート時のContent-Disposition
     */
    public enum ExportDisposition {
        INLINE, ATTACHMENT
    }

    /**
     * PDF設定
     */
    public record PdfSettings(
            String fontFamily,
            BigDecimal titleFontSize,
            BigDecimal dateFontSize,
            BigDecimal fullNameFontSize,
            BigDecimal sectionHeadingFontSize,
            String tableHeaderColor) {
    }
}
