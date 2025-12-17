import type { Project, SectionName } from "@/features/resume";
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

/**
 * ペイロードを構築する
 * @param sectionOrType セクション名またはエントリータイプ
 * @param entry エントリーデータ
 * @returns API送信用ペイロード
 */
export const buildPayloadForEntry = (sectionOrType: SectionName | string, entry: any): any => {
    switch (sectionOrType) {
        case "career":
            return {
                companyName: entry.companyName,
                startDate: entry.startDate,
                endDate: entry.endDate,
                isActive: entry.active,
            };
        case "project": {
            const p = entry as Project;
            return {
                companyName: p.companyName,
                startDate: p.startDate,
                endDate: p.endDate,
                isActive: p.active,
                name: p.name,
                overview: p.overview,
                teamComp: p.teamComp,
                role: p.role,
                achievement: p.achievement,
                requirements: p.process.requirements,
                basicDesign: p.process.basicDesign,
                detailedDesign: p.process.detailedDesign,
                implementation: p.process.implementation,
                integrationTest: p.process.integrationTest,
                systemTest: p.process.systemTest,
                maintenance: p.process.maintenance,
                frontendLanguages: p.techStack.frontend.languages,
                frontendFrameworks: p.techStack.frontend.frameworks,
                frontendLibraries: p.techStack.frontend.libraries,
                frontendBuildTools: p.techStack.frontend.buildTools,
                frontendPackageManagers: p.techStack.frontend.packageManagers,
                frontendLinters: p.techStack.frontend.linters,
                frontendFormatters: p.techStack.frontend.formatters,
                frontendTestingTools: p.techStack.frontend.testingTools,
                backendLanguages: p.techStack.backend.languages,
                backendFrameworks: p.techStack.backend.frameworks,
                backendLibraries: p.techStack.backend.libraries,
                backendBuildTools: p.techStack.backend.buildTools,
                backendPackageManagers: p.techStack.backend.packageManagers,
                backendLinters: p.techStack.backend.linters,
                backendFormatters: p.techStack.backend.formatters,
                backendTestingTools: p.techStack.backend.testingTools,
                ormTools: p.techStack.backend.ormTools,
                auth: p.techStack.backend.auth,
                clouds: p.techStack.infrastructure.clouds,
                operatingSystems: p.techStack.infrastructure.operatingSystems,
                containers: p.techStack.infrastructure.containers,
                databases: p.techStack.infrastructure.databases,
                webServers: p.techStack.infrastructure.webServers,
                ciCdTools: p.techStack.infrastructure.ciCdTools,
                iacTools: p.techStack.infrastructure.iacTools,
                monitoringTools: p.techStack.infrastructure.monitoringTools,
                loggingTools: p.techStack.infrastructure.loggingTools,
                sourceControls: p.techStack.tools.sourceControls,
                projectManagements: p.techStack.tools.projectManagements,
                communicationTools: p.techStack.tools.communicationTools,
                documentationTools: p.techStack.tools.documentationTools,
                apiDevelopmentTools: p.techStack.tools.apiDevelopmentTools,
                designTools: p.techStack.tools.designTools,
                editors: p.techStack.tools.editors,
                developmentEnvironments: p.techStack.tools.developmentEnvironments,
            };
        }
        case "certification":
            return {
                name: entry.name,
                date: entry.date,
            };
        case "portfolio":
            return {
                name: entry.name,
                overview: entry.overview,
                techStack: entry.techStack,
                link: entry.link,
            };
        case "socialLink":
            return {
                name: entry.name,
                link: entry.link,
            };
        case "selfPromotion":
            return {
                title: entry.title,
                content: entry.content,
            };
        default:
            return entry;
    }
};
