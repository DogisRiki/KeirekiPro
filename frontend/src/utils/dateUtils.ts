import dayjs from "dayjs";

/**
 * 日付文字列を「YYYY/MM」の文字列に整形する
 * @param date 日付文字列
 * @returns パースされた日付文字列
 */
export const formatDate = (date: string): string => {
    if (!date) return "";
    return dayjs(date).format("YYYY/MM");
};

/**
 * ISO文字列等の日付を「YYYY年M月D日 H:mm:ss」に整形する
 * @param date 日付文字列
 * @returns パースされた日付文字列
 */
export const formatDateTimeJa = (date: string): string => {
    if (!date) return "";

    // 小数秒がミリ秒(3桁)を超える場合は切り捨て
    const normalized = date.replace(/(\.\d{3})\d+/, "$1");

    const d = dayjs(normalized);
    if (!d.isValid()) return "";

    // 半角スペースを入れ、時はゼロ埋めしない、分秒はゼロ埋め
    return d.format("YYYY年M月D日 H:mm:ss");
};
