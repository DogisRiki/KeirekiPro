import dayjs from "dayjs";

/**
 * 日付文字列をYYYY/MMの文字列にパースする
 * @param date 日付文字列
 * @returns パースされた日付文字列
 */
export const formatDate = (date: string): string => {
    if (!date) return "";
    return dayjs(date).format("YYYY/MM");
};
