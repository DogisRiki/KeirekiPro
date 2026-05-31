package com.example.keirekipro.usecase.resume.command;

import java.math.BigDecimal;

import com.example.keirekipro.usecase.resume.export.ExportFormat;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * 職務経歴書エクスポートユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class ExportResumeCommand {

    private ExportFormat format;

    private ExportDisposition disposition;

    private PdfSettings pdfSettings;

    public boolean isPreview() {
        return disposition == ExportDisposition.INLINE;
    }

    /**
     * エクスポートレスポンスのContent-Disposition種別
     */
    public enum ExportDisposition {
        INLINE, ATTACHMENT
    }

    /**
     * エクスポートリクエストで指定されたPDF描画設定
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
