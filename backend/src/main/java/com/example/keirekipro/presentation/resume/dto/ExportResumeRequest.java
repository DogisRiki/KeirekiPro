package com.example.keirekipro.presentation.resume.dto;

import java.math.BigDecimal;
import java.util.Locale;

import com.example.keirekipro.usecase.resume.dto.ExportResumeCommand;
import com.example.keirekipro.usecase.resume.export.ExportFormat;
import com.fasterxml.jackson.annotation.JsonProperty;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.Valid;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

/**
 * 職務経歴書エクスポートリクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class ExportResumeRequest {

    @NotBlank(message = "エクスポート形式は入力必須です。")
    @Pattern(regexp = "pdf|markdown", message = "エクスポート形式が不正です。")
    private String format;

    @NotBlank(message = "出力方法は入力必須です。")
    @Pattern(regexp = "inline|attachment", message = "出力方法が不正です。")
    private String disposition;

    @Valid
    private PdfSettingsRequest pdfSettings;

    /**
     * PDFエクスポート時はPDF設定を必須にする
     */
    @AssertTrue(message = "PDF設定は入力必須です。")
    public boolean isPdfSettingsRequired() {
        return !"pdf".equals(format) || pdfSettings != null;
    }

    /**
     * ユースケースコマンドへ変換する
     */
    public ExportResumeCommand toCommand() {
        ExportResumeCommand.PdfSettings commandPdfSettings = null;
        if (pdfSettings != null) {
            commandPdfSettings = new ExportResumeCommand.PdfSettings(
                    pdfSettings.getFontFamily(),
                    pdfSettings.getFontSizes().getTitle(),
                    pdfSettings.getFontSizes().getDate(),
                    pdfSettings.getFontSizes().getFullName(),
                    pdfSettings.getFontSizes().getSectionHeading(),
                    pdfSettings.getTableHeaderColor().toCssColor());
        }

        return new ExportResumeCommand(
                "pdf".equals(format) ? ExportFormat.PDF : ExportFormat.MARKDOWN,
                "inline".equals(disposition)
                        ? ExportResumeCommand.ExportDisposition.INLINE
                        : ExportResumeCommand.ExportDisposition.ATTACHMENT,
                commandPdfSettings);
    }

    /**
     * PDF設定リクエスト
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class PdfSettingsRequest {

        @NotBlank(message = "フォント種類は入力必須です。")
        @Pattern(regexp = "NotoSansJP|NotoSerifJP", message = "フォント種類が不正です。")
        private String fontFamily;

        @Valid
        @NotNull(message = "フォントサイズは入力必須です。")
        private FontSizesRequest fontSizes;

        @Valid
        @NotNull(message = "表ヘッダー色は入力必須です。")
        private TableHeaderColorRequest tableHeaderColor;
    }

    /**
     * フォントサイズリクエスト
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class FontSizesRequest {

        @NotNull(message = "タイトルフォントサイズは入力必須です。")
        @DecimalMin(value = "6.0", message = "タイトルフォントサイズは6以上で入力してください。")
        @DecimalMax(value = "72.0", message = "タイトルフォントサイズは72以下で入力してください。")
        private BigDecimal title;

        @NotNull(message = "日付フォントサイズは入力必須です。")
        @DecimalMin(value = "6.0", message = "日付フォントサイズは6以上で入力してください。")
        @DecimalMax(value = "72.0", message = "日付フォントサイズは72以下で入力してください。")
        private BigDecimal date;

        @NotNull(message = "氏名フォントサイズは入力必須です。")
        @DecimalMin(value = "6.0", message = "氏名フォントサイズは6以上で入力してください。")
        @DecimalMax(value = "72.0", message = "氏名フォントサイズは72以下で入力してください。")
        private BigDecimal fullName;

        @NotNull(message = "セクション見出しフォントサイズは入力必須です。")
        @DecimalMin(value = "6.0", message = "セクション見出しフォントサイズは6以上で入力してください。")
        @DecimalMax(value = "72.0", message = "セクション見出しフォントサイズは72以下で入力してください。")
        private BigDecimal sectionHeading;
    }

    /**
     * 表ヘッダー色リクエスト
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class TableHeaderColorRequest {

        @Pattern(regexp = "^[0-9a-fA-F]{6}$", message = "カラーコードが不正です。")
        private String hex;

        @Valid
        private RgbRequest rgb;

        /**
         * カラーコードまたはRGBのどちらか一方だけを必須にする
         */
        @AssertTrue(message = "表ヘッダー色が不正です。")
        public boolean isSpecifiedOnce() {
            return (hex != null && rgb == null) || (hex == null && rgb != null);
        }

        /**
         * CSSカラー値へ変換する
         */
        public String toCssColor() {
            if (hex != null) {
                return "#" + hex.toLowerCase(Locale.ROOT);
            }
            return String.format("#%02x%02x%02x", rgb.getRed(), rgb.getGreen(), rgb.getBlue());
        }
    }

    /**
     * RGBリクエスト
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class RgbRequest {

        @NotNull(message = "Rは入力必須です。")
        @Min(value = 0, message = "Rは0以上で入力してください。")
        @Max(value = 255, message = "Rは255以下で入力してください。")
        @JsonProperty("r")
        private Integer red;

        @NotNull(message = "Gは入力必須です。")
        @Min(value = 0, message = "Gは0以上で入力してください。")
        @Max(value = 255, message = "Gは255以下で入力してください。")
        @JsonProperty("g")
        private Integer green;

        @NotNull(message = "Bは入力必須です。")
        @Min(value = 0, message = "Bは0以上で入力してください。")
        @Max(value = 255, message = "Bは255以下で入力してください。")
        @JsonProperty("b")
        private Integer blue;
    }
}
