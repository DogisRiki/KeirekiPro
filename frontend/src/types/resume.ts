/**
 * 職務経歴書
 */
export interface Resume {
    id: string;
    name: string; // 職務経歴書名
    date: string; // 日付
    lastName: string; // 姓
    firstName: string; // 名
    autoSaveEnabled: boolean; // 自動保存設定
    createdAt: string; // 作成日時
    updatedAt: string; // 更新日時
    careers: Career[];
    projects: Project[];
    certifications: Certification[];
    portfolios: Portfolio[];
    socialLinks: SocialLink[];
    selfPromotions: SelfPromotion[];
}

/**
 * 職歴
 */
export interface Career {
    id: string;
    companyName: string; // 会社名
    startDate: string; // 入社年月
    endDate: string | null; // 退職年月
    isEmployed: boolean; // 在職中フラグ
    orderNo: number; // 並び順
}

/**
 * 職務内容 (Project)
 */
export interface Project {
    id: string;
    companyName: string; // 会社名
    projectName: string; // プロジェクト名
    startDate: string; // 開始年月
    endDate: string | null; // 終了年月
    isAssigned: boolean; // 担当中フラグ
    overview: string; // プロジェクト概要
    teamComp: string; // チーム構成
    role: string; // 役割
    achievement: string; // 成果
    process: Process; // 作業工程
    techStack: TechStack; // 技術スタック
    orderNo: number; // 並び順
}

/**
 * 資格
 */
export interface Certification {
    id: string;
    name: string; // 資格名
    date: string; // 取得年月
    orderNo: number; // 並び順
}

/**
 * ポートフォリオ
 */
export interface Portfolio {
    id: string;
    name: string; // ポートフォリオ名
    overview: string; // ポートフォリオ概要
    link: string; // リンク
    teckStack: string; // 技術スタック
    orderNo: number; // 並び順
}

/**
 * ソーシャルリンク
 */
export interface SocialLink {
    id: string;
    name: string; // ソーシャル名
    link: string; // リンク
    orderNo: number; // 並び順
}

/**
 * 自己PR
 */
export interface SelfPromotion {
    id: string;
    title: string; // タイトル
    content: string; // コンテンツ
    orderNo: number; // 並び順
}

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
