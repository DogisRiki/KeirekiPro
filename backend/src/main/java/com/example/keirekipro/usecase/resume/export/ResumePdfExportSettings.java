package com.example.keirekipro.usecase.resume.export;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Locale;

/**
 * PDFエクスポート設定
 */
public record ResumePdfExportSettings(
        String fontFamily,
        BigDecimal titleFontSize,
        BigDecimal dateFontSize,
        BigDecimal fullNameFontSize,
        BigDecimal sectionHeadingFontSize,
        String tableHeaderColor) {

    private static final BigDecimal MIN_FONT_SIZE = BigDecimal.valueOf(6);
    private static final BigDecimal MAX_FONT_SIZE = BigDecimal.valueOf(72);

    /**
     * デフォルト設定
     */
    public static ResumePdfExportSettings defaults() {
        return new ResumePdfExportSettings(
                "Noto Sans JP",
                BigDecimal.valueOf(16),
                BigDecimal.valueOf(10),
                BigDecimal.valueOf(10),
                BigDecimal.valueOf(11.5),
                "#d9d9d9");
    }

    /**
     * 入力値から正規化済み設定を作成する
     */
    public static ResumePdfExportSettings normalize(
            String fontFamily,
            BigDecimal titleFontSize,
            BigDecimal dateFontSize,
            BigDecimal fullNameFontSize,
            BigDecimal sectionHeadingFontSize,
            String tableHeaderColor) {
        return new ResumePdfExportSettings(
                toCssFontFamily(fontFamily),
                normalizeFontSize(titleFontSize),
                normalizeFontSize(dateFontSize),
                normalizeFontSize(fullNameFontSize),
                normalizeFontSize(sectionHeadingFontSize),
                normalizeColor(tableHeaderColor));
    }

    private static String toCssFontFamily(String fontFamily) {
        return switch (fontFamily) {
            case "NotoSansJP" -> "Noto Sans JP";
            case "NotoSerifJP" -> "Noto Serif JP";
            default -> throw new IllegalArgumentException("存在しないフォント種類です。");
        };
    }

    private static BigDecimal normalizeFontSize(BigDecimal value) {
        if (value.compareTo(MIN_FONT_SIZE) < 0 || value.compareTo(MAX_FONT_SIZE) > 0) {
            throw new IllegalArgumentException("フォントサイズが不正です。");
        }

        BigDecimal floor = value.setScale(0, RoundingMode.FLOOR);
        BigDecimal fraction = value.subtract(floor);
        int tenths = fraction.multiply(BigDecimal.TEN).setScale(0, RoundingMode.DOWN).intValue();

        BigDecimal normalized;
        if (tenths <= 2) {
            normalized = floor;
        } else if (tenths <= 7) {
            normalized = floor.add(BigDecimal.valueOf(0.5));
        } else {
            normalized = floor.add(BigDecimal.ONE);
        }
        return normalized;
    }

    private static String normalizeColor(String color) {
        if (color == null || !color.matches("^#[0-9a-fA-F]{6}$")) {
            throw new IllegalArgumentException("表ヘッダー色が不正です。");
        }
        return color.toLowerCase(Locale.ROOT);
    }
}
