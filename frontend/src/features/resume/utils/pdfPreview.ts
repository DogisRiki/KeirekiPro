import type { ResumePdfSettings } from "@/features/resume";

export const PDF_FONT_SIZE_OPTIONS = [6, 8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 32, 36, 48, 64, 72];

export const DEFAULT_RESUME_PDF_SETTINGS: ResumePdfSettings = {
    fontFamily: "NotoSansJP",
    fontSizes: {
        title: 16,
        date: 10,
        fullName: 10,
        sectionHeading: 11.5,
    },
    tableHeaderColor: {
        hex: "d9d9d9",
    },
};

/**
 * フォントサイズをExcelに近い0.5刻みへ補正する
 */
export const normalizePdfFontSize = (value: number): number => {
    const clamped = Math.min(72, Math.max(6, value));
    const floor = Math.floor(clamped);
    const tenths = Math.floor((clamped - floor) * 10);

    if (tenths <= 2) {
        return floor;
    }
    if (tenths <= 7) {
        return floor + 0.5;
    }
    return floor + 1;
};

/**
 * カラーコードをRGBへ変換する
 */
export const hexToRgb = (hex: string) => {
    const normalized = hex.replace("#", "").toLowerCase();
    return {
        r: Number.parseInt(normalized.slice(0, 2), 16),
        g: Number.parseInt(normalized.slice(2, 4), 16),
        b: Number.parseInt(normalized.slice(4, 6), 16),
    };
};

/**
 * RGBをカラーコードへ変換する
 */
export const rgbToHex = (r: number, g: number, b: number): string =>
    [r, g, b].map((value) => value.toString(16).padStart(2, "0")).join("");

const getTableHeaderHex = (settings: ResumePdfSettings): string =>
    (
        settings.tableHeaderColor.hex ??
        rgbToHex(
            settings.tableHeaderColor.rgb?.r ?? 217,
            settings.tableHeaderColor.rgb?.g ?? 217,
            settings.tableHeaderColor.rgb?.b ?? 217,
        )
    ).toLowerCase();

/**
 * PDF設定が同一か判定する
 */
export const isSameResumePdfSettings = (left: ResumePdfSettings, right: ResumePdfSettings): boolean =>
    left.fontFamily === right.fontFamily &&
    left.fontSizes.title === right.fontSizes.title &&
    left.fontSizes.date === right.fontSizes.date &&
    left.fontSizes.fullName === right.fontSizes.fullName &&
    left.fontSizes.sectionHeading === right.fontSizes.sectionHeading &&
    getTableHeaderHex(left) === getTableHeaderHex(right);

/**
 * PDF設定をAPI送信用に整える
 */
export const buildResumePdfSettingsPayload = (settings: ResumePdfSettings): ResumePdfSettings => {
    const hex = getTableHeaderHex(settings);

    return {
        ...settings,
        fontSizes: {
            title: normalizePdfFontSize(settings.fontSizes.title),
            date: normalizePdfFontSize(settings.fontSizes.date),
            fullName: normalizePdfFontSize(settings.fontSizes.fullName),
            sectionHeading: normalizePdfFontSize(settings.fontSizes.sectionHeading),
        },
        tableHeaderColor: {
            hex: hex.toLowerCase(),
        },
    };
};
