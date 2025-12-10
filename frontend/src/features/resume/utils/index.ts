import type { SectionName } from "@/features/resume";
import { sections, TEMP_ID_PREFIX } from "@/features/resume";
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
                secondary: formatPeriod(entry.startDate, entry.endDate, entry.active),
            };
        case "project":
            return {
                primary: entry.name,
                secondary: formatPeriod(entry.startDate, entry.endDate, entry.active),
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
 * @param startDate 開始日（"yyyy-MM"形式）
 * @param endDate 終了日（"yyyy-MM"形式）。省略可能
 * @param isCurrent 現在も継続中かどうか。trueの場合、終了日の代わりに「現在」と表示
 */
const formatPeriod = (startDate: string, endDate?: string | null, isCurrent?: boolean): string => {
    if (!startDate) return "";

    const formatYm = (date: string) => {
        return dayjs(date).format("YYYY/MM");
    };

    return `${formatYm(startDate)} - ${isCurrent ? "現在" : endDate ? formatYm(endDate) : ""}`;
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

/**
 * 一時IDかどうかを判定する
 * @param id ID文字列
 * @returns 一時IDの場合true
 */
export const isTempId = (id: string | null | undefined): boolean => {
    if (!id) return true;
    return id.startsWith(TEMP_ID_PREFIX);
};

/**
 * APIに送信する用のIDを取得する
 * 一時IDの場合はnullを返す
 * @param id ID文字列
 * @returns APIに送信するID（一時IDの場合はnull）
 */
export const getApiId = (id: string | null | undefined): string | null => {
    if (!id || isTempId(id)) return null;
    return id;
};
