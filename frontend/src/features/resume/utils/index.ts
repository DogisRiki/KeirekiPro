import { SectionName, sections } from "@/features/resume";
import { formatDate } from "@/utils";
import dayjs from "dayjs";
import React from "react";

/**
 * アクティブなセクションを生成するファクトリー
 */
export const createCurrentSection = (activeSection: SectionName): React.ReactElement => {
    const currentSection = sections.find((section) => section.key === activeSection)!;
    return React.createElement(currentSection.component);
};

/**
 * エントリーに表示するテキストを取得する
 */
export const getEntryText = (activeSection: SectionName, entry: any) => {
    if (activeSection === "basicInfo") {
        return null;
    }
    switch (activeSection) {
        case "career":
            return {
                primary: entry.companyName,
                secondary: formatPeriod(entry.startDate, entry.endDate, entry.isEmployed),
            };
        case "project":
            return {
                primary: entry.companyName,
                secondary: formatPeriod(entry.startDate, entry.endDate, entry.isAssigned),
            };
        case "certification":
            return {
                primary: entry.name,
                secondary: formatDate(entry.date),
            };
        case "portfolio":
            return { primary: entry.name, secondary: entry.link };
        case "socialLink":
            return { primary: entry.name, secondary: entry.link };
        case "selfPromotion":
            return { primary: entry.title, secondary: entry.content };
        default:
            return {};
    }
};

/**
 * 期間を「YYYY/MM - YYYY/MM」形式または「YYYY/MM - 現在」形式の文字列に変換する
 * @param startDate 開始日（YYYY-MM-DD形式）
 * @param endDate 終了日（YYYY-MM-DD形式）。省略可能
 * @param isCurrent 現在も継続中かどうか。trueの場合、終了日の代わりに「現在」と表示
 * @returns フォーマットされた期間文字列
 * @example
 * // 開始と終了が指定された場合
 * formatPeriod('2022-01-01', '2023-12-31') // '2022/01 - 2023/12'
 * // 現在進行中の場合
 * formatPeriod('2022-01-01', null, true) // '2022/01 - 現在'
 * // 開始日のみの場合
 * formatPeriod('2022-01-01') // '2022/01 - '
 */
const formatPeriod = (startDate: string, endDate?: string | null, isCurrent?: boolean): string => {
    if (!startDate) return "";

    const formatDate = (date: string) => {
        return dayjs(date).format("YYYY/MM");
    };

    return `${formatDate(startDate)} - ${isCurrent ? "現在" : endDate ? formatDate(endDate) : ""}`;
};

/**
 * セクション名から対応する職務経歴書オブジェクトのキーを取得する
 * @param activeSection アクティブなセクション
 * @returns 対応するオブジェクトのキー
 */
export const getResumeKey = (activeSection: SectionName) => {
    switch (activeSection) {
        case "career":
            return "careers";
        case "project":
            return "projects";
        case "certification":
            return "certifications";
        case "portfolio":
            return "portfolios";
        case "socialLink":
            return "socialLinks";
        case "selfPromotion":
            return "selfPromotions";
    }
};
