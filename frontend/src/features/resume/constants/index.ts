import type { ProcessMap, SectionInfo } from "@/features/resume";
import {
    BasicInfoSection,
    CareerSection,
    CertificationSection,
    PortfolioSection,
    ProjectSection,
    SelfPromotionSection,
    SociealLinkSection,
} from "@/features/resume";

/**
 * セクション情報一覧
 */
export const sections: SectionInfo[] = [
    { key: "basicInfo", label: "基本", type: "single", component: BasicInfoSection },
    { key: "career", label: "職歴", type: "list", component: CareerSection },
    { key: "project", label: "プロジェクト", type: "list", component: ProjectSection },
    { key: "certification", label: "保有資格", type: "list", component: CertificationSection },
    { key: "portfolio", label: "ポートフォリオ", type: "list", component: PortfolioSection },
    { key: "socialLink", label: "SNS", type: "list", component: SociealLinkSection },
    { key: "selfPromotion", label: "自己PR", type: "list", component: SelfPromotionSection },
] as const;

/**
 * 作業工程のマッピング
 */
export const processList: ProcessMap = {
    requirements: "要件定義",
    basicDesign: "基本設計",
    detailedDesign: "詳細設計",
    implementation: "実装・単体テスト",
    integrationTest: "結合テスト",
    systemTest: "総合テスト",
    maintenance: "運用・保守",
} as const;

/**
 * 技術スタックのカテゴリマッピング
 */
export const techStackInfo = [
    {
        title: "フロントエンド",
        fields: [
            { label: "言語", path: ["frontend", "languages"] },
            { label: "フレームワーク", path: ["frontend", "frameworks"] },
            { label: "ライブラリ", path: ["frontend", "libraries"] },
            { label: "ビルドツール", path: ["frontend", "buildTools"] },
            { label: "パッケージマネージャー", path: ["frontend", "packageManagers"] },
            { label: "リンター", path: ["frontend", "linters"] },
            { label: "フォーマッター", path: ["frontend", "formatters"] },
            { label: "テストツール", path: ["frontend", "testingTools"] },
        ],
    },
    {
        title: "バックエンド",
        fields: [
            { label: "言語", path: ["backend", "languages"] },
            { label: "フレームワーク", path: ["backend", "frameworks"] },
            { label: "ライブラリ", path: ["backend", "libraries"] },
            { label: "ビルドツール", path: ["backend", "buildTools"] },
            { label: "パッケージマネージャー", path: ["backend", "packageManagers"] },
            { label: "リンター", path: ["backend", "linters"] },
            { label: "フォーマッター", path: ["backend", "formatters"] },
            { label: "テストツール", path: ["backend", "testingTools"] },
            { label: "ORM", path: ["backend", "ormTools"] },
            { label: "認証/認可", path: ["backend", "auth"] },
        ],
    },
    {
        title: "インフラ",
        fields: [
            { label: "クラウド", path: ["infrastructure", "clouds"] },
            { label: "OS", path: ["infrastructure", "operatingSystems"] },
            { label: "コンテナ", path: ["infrastructure", "containers"] },
            { label: "データベース", path: ["infrastructure", "databases"] },
            { label: "Webサーバー", path: ["infrastructure", "webServers"] },
            { label: "CI/CD", path: ["infrastructure", "ciCdTools"] },
            { label: "IaC", path: ["infrastructure", "iacTools"] },
            { label: "監視", path: ["infrastructure", "monitoringTools"] },
            { label: "ロギング", path: ["infrastructure", "loggingTools"] },
        ],
    },
    {
        title: "開発支援ツール",
        fields: [
            { label: "ソース管理", path: ["tools", "sourceControls"] },
            { label: "プロジェクト管理", path: ["tools", "projectManagements"] },
            { label: "コミュニケーション", path: ["tools", "communicationTools"] },
            { label: "ドキュメント", path: ["tools", "documentationTools"] },
            { label: "API開発", path: ["tools", "apiDevelopmentTools"] },
            { label: "デザイン", path: ["tools", "designTools"] },
            { label: "エディタ/IDE", path: ["tools", "editors"] },
            { label: "開発環境", path: ["tools", "developmentEnvironments"] },
        ],
    },
] as const;

/**
 * 一時IDのプレフィックス
 */
export const TEMP_ID_PREFIX = "temp_";
