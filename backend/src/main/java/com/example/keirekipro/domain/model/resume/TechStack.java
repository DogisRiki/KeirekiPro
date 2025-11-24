package com.example.keirekipro.domain.model.resume;

import java.util.List;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * 技術スタック
 */
@Getter
@EqualsAndHashCode
public class TechStack {

    /**
     * フロントエンド
     */
    private final Frontend frontend;

    /**
     * バックエンド
     */
    private final Backend backend;

    /**
     * インフラ
     */
    private final Infrastructure infrastructure;

    /**
     * 開発支援ツール
     */
    private final Tools tools;

    private TechStack(Frontend frontend, Backend backend, Infrastructure infrastructure, Tools tools) {
        this.frontend = frontend;
        this.backend = backend;
        this.infrastructure = infrastructure;
        this.tools = tools;
    }

    /**
     * ファクトリーメソッド
     *
     * @param frontend       フロントエンド
     * @param backend        バックエンド
     * @param infrastructure インフラ
     * @param tools          開発支援ツール
     * @return 値オブジェクト
     */
    public static TechStack create(Frontend frontend, Backend backend,
            Infrastructure infrastructure, Tools tools) {
        return new TechStack(frontend, backend, infrastructure, tools);
    }

    /**
     * フロントエンド技術スタック
     */
    @Getter
    @EqualsAndHashCode
    public static class Frontend {

        /**
         * 開発言語
         */
        private final List<String> languages;

        /**
         * フレームワーク
         */
        private final String framework;

        /**
         * ライブラリ
         */
        private final List<String> libraries;

        /**
         * ビルドツール
         */
        private final String buildTool;

        /**
         * パッケージマネージャー
         */
        private final String packageManager;

        /**
         * リンター
         */
        private final List<String> linters;

        /**
         * フォーマッター
         */
        private final List<String> formatters;

        /**
         * テストツール
         */
        private final List<String> testingTools;

        private Frontend(List<String> languages, String framework, List<String> libraries,
                String buildTool, String packageManager, List<String> linters,
                List<String> formatters, List<String> testingTools) {
            this.languages = languages;
            this.framework = framework;
            this.libraries = libraries;
            this.buildTool = buildTool;
            this.packageManager = packageManager;
            this.linters = linters;
            this.formatters = formatters;
            this.testingTools = testingTools;
        }

        /**
         * ファクトリーメソッド
         *
         * @param languages      開発言語
         * @param framework      フレームワーク
         * @param libraries      ライブラリ
         * @param buildTool      ビルドツール
         * @param packageManager パッケージマネージャー
         * @param linters        リンター
         * @param formatters     フォーマッター
         * @param testingTools   テストツール
         * @return 値オブジェクト
         */
        public static Frontend create(List<String> languages, String framework,
                List<String> libraries, String buildTool, String packageManager,
                List<String> linters, List<String> formatters, List<String> testingTools) {
            return new Frontend(languages, framework, libraries, buildTool,
                    packageManager, linters, formatters, testingTools);
        }
    }

    /**
     * バックエンド技術スタック
     */
    @Getter
    @EqualsAndHashCode
    public static class Backend {

        /**
         * 開発言語
         */
        private final List<String> languages;

        /**
         * フレームワーク
         */
        private final String framework;

        /**
         * ライブラリ
         */
        private final List<String> libraries;

        /**
         * ビルドツール
         */
        private final String buildTool;

        /**
         * パッケージマネージャー
         */
        private final String packageManager;

        /**
         * リンター
         */
        private final List<String> linters;

        /**
         * フォーマッター
         */
        private final List<String> formatters;

        /**
         * テストツール
         */
        private final List<String> testingTools;

        /**
         * ORM
         */
        private final List<String> ormTools;

        /**
         * 認証
         */
        private final List<String> auth;

        private Backend(List<String> languages, String framework, List<String> libraries,
                String buildTool, String packageManager, List<String> linters,
                List<String> formatters, List<String> testingTools,
                List<String> ormTools, List<String> auth) {
            this.languages = languages;
            this.framework = framework;
            this.libraries = libraries;
            this.buildTool = buildTool;
            this.packageManager = packageManager;
            this.linters = linters;
            this.formatters = formatters;
            this.testingTools = testingTools;
            this.ormTools = ormTools;
            this.auth = auth;
        }

        /**
         * ファクトリーメソッド
         *
         * @param languages      開発言語
         * @param framework      フレームワーク
         * @param libraries      ライブラリ
         * @param buildTool      ビルドツール
         * @param packageManager パッケージマネージャー
         * @param linters        リンター
         * @param formatters     フォーマッター
         * @param testingTools   テストツール
         * @param ormTools       ORM
         * @param auth           認証
         * @return 値オブジェクト
         */
        public static Backend create(List<String> languages, String framework,
                List<String> libraries, String buildTool, String packageManager,
                List<String> linters, List<String> formatters, List<String> testingTools,
                List<String> ormTools, List<String> auth) {
            return new Backend(languages, framework, libraries, buildTool,
                    packageManager, linters, formatters, testingTools,
                    ormTools, auth);
        }
    }

    /**
     * インフラ
     */
    @Getter
    @EqualsAndHashCode
    public static class Infrastructure {

        /**
         * クラウド
         */
        private final List<String> clouds;

        /**
         * OS
         */
        private final String operatingSystem;

        /**
         * コンテナ
         */
        private final List<String> containers;

        /**
         * データベース
         */
        private final String database;

        /**
         * Webサーバー
         */
        private final String webServer;

        /**
         * CI/CD
         */
        private final String ciCdTool;

        /**
         * IaC
         */
        private final List<String> iacTools;

        /**
         * 監視
         */
        private final List<String> monitoringTools;

        /**
         * ロギング
         */
        private final List<String> loggingTools;

        private Infrastructure(List<String> clouds, String operatingSystem,
                List<String> containers, String database, String webServer,
                String ciCdTool, List<String> iacTools, List<String> monitoringTools,
                List<String> loggingTools) {
            this.clouds = clouds;
            this.operatingSystem = operatingSystem;
            this.containers = containers;
            this.database = database;
            this.webServer = webServer;
            this.ciCdTool = ciCdTool;
            this.iacTools = iacTools;
            this.monitoringTools = monitoringTools;
            this.loggingTools = loggingTools;
        }

        /**
         * ファクトリーメソッド
         *
         * @param clouds          クラウド
         * @param operatingSystem OS
         * @param containers      コンテナ
         * @param database        データベース
         * @param webServer       Webサーバー
         * @param ciCdTool        CI/CD
         * @param iacTools        IaC
         * @param monitoringTools 監視
         * @param loggingTools    ロギング
         * @return 値オブジェクト
         */
        public static Infrastructure create(List<String> clouds, String operatingSystem,
                List<String> containers, String database, String webServer,
                String ciCdTool, List<String> iacTools, List<String> monitoringTools,
                List<String> loggingTools) {
            return new Infrastructure(clouds, operatingSystem, containers, database,
                    webServer, ciCdTool, iacTools, monitoringTools, loggingTools);
        }
    }

    /**
     * 開発支援ツール
     */
    @Getter
    @EqualsAndHashCode
    public static class Tools {

        /**
         * ソース管理
         */
        private final String sourceControl;

        /**
         * プロジェクト管理
         */
        private final String projectManagement;

        /**
         * コミュニケーション
         */
        private final String communicationTool;

        /**
         * ドキュメント
         */
        private final List<String> documentationTools;

        /**
         * API開発
         */
        private final List<String> apiDevelopmentTools;

        /**
         * デザイン
         */
        private final List<String> designTools;

        /**
         * エディタ
         */
        private final String editor;

        /**
         * 開発環境
         */
        private final String developmentEnvironment;

        private Tools(String sourceControl, String projectManagement,
                String communicationTool, List<String> documentationTools,
                List<String> apiDevelopmentTools, List<String> designTools,
                String editor, String developmentEnvironment) {
            this.sourceControl = sourceControl;
            this.projectManagement = projectManagement;
            this.communicationTool = communicationTool;
            this.documentationTools = documentationTools;
            this.apiDevelopmentTools = apiDevelopmentTools;
            this.designTools = designTools;
            this.editor = editor;
            this.developmentEnvironment = developmentEnvironment;
        }

        /**
         * ファクトリーメソッド
         *
         * @param sourceControl          ソース管理
         * @param projectManagement      プロジェクト管理
         * @param communicationTool      コミュニケーション
         * @param documentationTools     ドキュメント
         * @param apiDevelopmentTools    API開発
         * @param designTools            デザイン
         * @param editor                 エディタ
         * @param developmentEnvironment 開発環境
         * @return 値オブジェクト
         */
        public static Tools create(String sourceControl, String projectManagement,
                String communicationTool, List<String> documentationTools,
                List<String> apiDevelopmentTools, List<String> designTools,
                String editor, String developmentEnvironment) {
            return new Tools(sourceControl, projectManagement, communicationTool,
                    documentationTools, apiDevelopmentTools, designTools,
                    editor, developmentEnvironment);
        }
    }
}
