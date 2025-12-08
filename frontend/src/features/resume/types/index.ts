import type React from "react";

/**
 * セクション名
 */
export type SectionName =
    | "basicInfo"
    | "career"
    | "project"
    | "certification"
    | "portfolio"
    | "socialLink"
    | "selfPromotion";

/**
 * セクション情報の定義
 */
export interface SectionInfo {
    key: SectionName;
    label: string; // 表示名
    type: "single" | "list"; // セクションタイプ(エントリーリストを表示するか否か)
    component: React.ComponentType; // 対応するコンポーネント
}

/**
 * 作業工程名
 */
export type ProcessName =
    | "要件定義"
    | "基本設計"
    | "詳細設計"
    | "実装・単体テスト"
    | "結合テスト"
    | "総合テスト"
    | "運用・保守";

/**
 * 作業工程
 */
export interface Process {
    requirements: boolean; // 要件定義
    basicDesign: boolean; // 基本設計
    detailedDesign: boolean; // 詳細設計
    implementation: boolean; // 実装・単体テスト
    integrationTest: boolean; // 結合テスト
    systemTest: boolean; // 総合テスト
    maintenance: boolean; // 運用・保守
}

/**
 * 作業工程バインド
 */
export type ProcessMap = Record<keyof Process, ProcessName>;

/**
 * 職歴
 */
export interface Career {
    id: string;
    companyName: string;
    startDate: string; // yyyy-MM
    endDate: string | null; // yyyy-MM
    active: boolean;
}

/**
 * プロジェクト用 技術スタック - フロントエンド
 */
export interface ProjectTechStackFrontend {
    languages: string[];
    framework: string | null;
    libraries: string[];
    buildTool: string | null;
    packageManager: string | null;
    linters: string[];
    formatters: string[];
    testingTools: string[];
}

/**
 * プロジェクト用 技術スタック - バックエンド
 */
export interface ProjectTechStackBackend {
    languages: string[];
    framework: string | null;
    libraries: string[];
    buildTool: string | null;
    packageManager: string | null;
    linters: string[];
    formatters: string[];
    testingTools: string[];
    ormTools: string[];
    auth: string[];
}

/**
 * プロジェクト用 技術スタック - インフラ
 */
export interface ProjectTechStackInfrastructure {
    clouds: string[];
    operatingSystem: string | null;
    containers: string[];
    database: string | null;
    webServer: string | null;
    ciCdTools: string | null;
    iacTools: string[];
    monitoringTools: string[];
    loggingTools: string[];
}

/**
 * プロジェクト用 技術スタック - 開発支援ツール
 */
export interface ProjectTechStackTools {
    sourceControl: string | null;
    projectManagement: string | null;
    communicationTool: string | null;
    documentationTools: string[];
    apiDevelopmentTools: string[];
    designTools: string[];
    editor: string | null;
    developmentEnvironment: string | null;
}

/**
 * プロジェクト用 技術スタック
 */
export interface ProjectTechStack {
    frontend: ProjectTechStackFrontend;
    backend: ProjectTechStackBackend;
    infrastructure: ProjectTechStackInfrastructure;
    tools: ProjectTechStackTools;
}

/**
 * プロジェクト
 */
export interface Project {
    id: string;
    companyName: string;
    startDate: string; // yyyy-MM-dd
    endDate: string | null; // yyyy-MM-dd
    active: boolean;
    name: string;
    overview: string;
    teamComp: string;
    role: string;
    achievement: string;
    process: Process;
    techStack: ProjectTechStack;
}

/**
 * 資格
 */
export interface Certification {
    id: string;
    name: string;
    date: string; // yyyy-MM-dd
}

/**
 * ポートフォリオ
 */
export interface Portfolio {
    id: string;
    name: string;
    overview: string;
    techStack: string;
    link: string;
}

/**
 * ソーシャルリンク
 */
export interface SocialLink {
    id: string;
    name: string;
    link: string;
}

/**
 * 自己PR
 */
export interface SelfPromotion {
    id: string;
    title: string;
    content: string;
}

/**
 * 職務経歴書
 */
export interface Resume {
    id: string;
    resumeName: string;
    date: string; // yyyy-MM-dd
    lastName: string | null;
    firstName: string | null;
    createdAt: string;
    updatedAt: string;
    careers: Career[];
    projects: Project[];
    certifications: Certification[];
    portfolios: Portfolio[];
    socialLinks: SocialLink[];
    selfPromotions: SelfPromotion[];
}

export interface TechStackFrontend {
    // フロントエンド
    languages: string[];
    frameworks: string[];
    libraries: string[];
    buildTools: string[];
    packageManagers: string[];
    linters: string[];
    formatters: string[];
    testingTools: string[];
}

export interface TechStackBackend {
    // バックエンド
    languages: string[];
    frameworks: string[];
    libraries: string[];
    buildTools: string[];
    packageManagers: string[];
    linters: string[];
    formatters: string[];
    testingTools: string[];
    ormTools: string[];
    auth: string[];
}

export interface TechStackInfrastructure {
    // インフラ
    clouds: string[];
    operatingSystems: string[];
    containers: string[];
    databases: string[];
    webServers: string[];
    ciCdTools: string[];
    iacTools: string[];
    monitoringTools: string[];
    loggingTools: string[];
}

export interface TechStackTools {
    // 開発支援ツール
    sourceControls: string[];
    projectManagements: string[];
    communicationTools: string[];
    documentationTools: string[];
    apiDevelopmentTools: string[];
    designTools: string[];
    editors: string[];
    developmentEnvironments: string[];
}

/**
 * 技術スタック
 */
export interface TechStack {
    frontend: TechStackFrontend;
    backend: TechStackBackend;
    infrastructure: TechStackInfrastructure;
    tools: TechStackTools;
}
