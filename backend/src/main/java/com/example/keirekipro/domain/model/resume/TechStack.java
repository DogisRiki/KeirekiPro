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
        private final List<String> frameworks;

        /**
         * ライブラリ
         */
        private final List<String> libraries;

        /**
         * ビルドツール
         */
        private final List<String> buildTools;

        /**
         * パッケージマネージャー
         */
        private final List<String> packageManagers;

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

        private Frontend(List<String> languages,
                List<String> frameworks,
                List<String> libraries,
                List<String> buildTools,
                List<String> packageManagers,
                List<String> linters,
                List<String> formatters,
                List<String> testingTools) {
            this.languages = languages;
            this.frameworks = frameworks;
            this.libraries = libraries;
            this.buildTools = buildTools;
            this.packageManagers = packageManagers;
            this.linters = linters;
            this.formatters = formatters;
            this.testingTools = testingTools;
        }

        /**
         * ファクトリーメソッド
         *
         * @param languages       開発言語
         * @param frameworks      フレームワーク
         * @param libraries       ライブラリ
         * @param buildTools      ビルドツール
         * @param packageManagers パッケージマネージャー
         * @param linters         リンター
         * @param formatters      フォーマッター
         * @param testingTools    テストツール
         * @return 値オブジェクト
         */
        public static Frontend create(List<String> languages,
                List<String> frameworks,
                List<String> libraries,
                List<String> buildTools,
                List<String> packageManagers,
                List<String> linters,
                List<String> formatters,
                List<String> testingTools) {
            return new Frontend(languages, frameworks, libraries, buildTools,
                    packageManagers, linters, formatters, testingTools);
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
        private final List<String> frameworks;

        /**
         * ライブラリ
         */
        private final List<String> libraries;

        /**
         * ビルドツール
         */
        private final List<String> buildTools;

        /**
         * パッケージマネージャー
         */
        private final List<String> packageManagers;

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

        private Backend(List<String> languages,
                List<String> frameworks,
                List<String> libraries,
                List<String> buildTools,
                List<String> packageManagers,
                List<String> linters,
                List<String> formatters,
                List<String> testingTools,
                List<String> ormTools,
                List<String> auth) {
            this.languages = languages;
            this.frameworks = frameworks;
            this.libraries = libraries;
            this.buildTools = buildTools;
            this.packageManagers = packageManagers;
            this.linters = linters;
            this.formatters = formatters;
            this.testingTools = testingTools;
            this.ormTools = ormTools;
            this.auth = auth;
        }

        /**
         * ファクトリーメソッド
         *
         * @param languages       開発言語
         * @param frameworks      フレームワーク
         * @param libraries       ライブラリ
         * @param buildTools      ビルドツール
         * @param packageManagers パッケージマネージャー
         * @param linters         リンター
         * @param formatters      フォーマッター
         * @param testingTools    テストツール
         * @param ormTools        ORM
         * @param auth            認証
         * @return 値オブジェクト
         */
        public static Backend create(List<String> languages,
                List<String> frameworks,
                List<String> libraries,
                List<String> buildTools,
                List<String> packageManagers,
                List<String> linters,
                List<String> formatters,
                List<String> testingTools,
                List<String> ormTools,
                List<String> auth) {
            return new Backend(languages, frameworks, libraries, buildTools,
                    packageManagers, linters, formatters, testingTools,
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
        private final List<String> operatingSystems;

        /**
         * コンテナ
         */
        private final List<String> containers;

        /**
         * データベース
         */
        private final List<String> databases;

        /**
         * Webサーバー
         */
        private final List<String> webServers;

        /**
         * CI/CD
         */
        private final List<String> ciCdTools;

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

        private Infrastructure(List<String> clouds,
                List<String> operatingSystems,
                List<String> containers,
                List<String> databases,
                List<String> webServers,
                List<String> ciCdTools,
                List<String> iacTools,
                List<String> monitoringTools,
                List<String> loggingTools) {
            this.clouds = clouds;
            this.operatingSystems = operatingSystems;
            this.containers = containers;
            this.databases = databases;
            this.webServers = webServers;
            this.ciCdTools = ciCdTools;
            this.iacTools = iacTools;
            this.monitoringTools = monitoringTools;
            this.loggingTools = loggingTools;
        }

        /**
         * ファクトリーメソッド
         *
         * @param clouds           クラウド
         * @param operatingSystems OS
         * @param containers       コンテナ
         * @param databases        データベース
         * @param webServers       Webサーバー
         * @param ciCdTools        CI/CD
         * @param iacTools         IaC
         * @param monitoringTools  監視
         * @param loggingTools     ロギング
         * @return 値オブジェクト
         */
        public static Infrastructure create(List<String> clouds,
                List<String> operatingSystems,
                List<String> containers,
                List<String> databases,
                List<String> webServers,
                List<String> ciCdTools,
                List<String> iacTools,
                List<String> monitoringTools,
                List<String> loggingTools) {
            return new Infrastructure(clouds, operatingSystems, containers, databases,
                    webServers, ciCdTools, iacTools, monitoringTools, loggingTools);
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
        private final List<String> sourceControls;

        /**
         * プロジェクト管理
         */
        private final List<String> projectManagements;

        /**
         * コミュニケーション
         */
        private final List<String> communicationTools;

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
        private final List<String> editors;

        /**
         * 開発環境
         */
        private final List<String> developmentEnvironments;

        private Tools(List<String> sourceControls,
                List<String> projectManagements,
                List<String> communicationTools,
                List<String> documentationTools,
                List<String> apiDevelopmentTools,
                List<String> designTools,
                List<String> editors,
                List<String> developmentEnvironments) {
            this.sourceControls = sourceControls;
            this.projectManagements = projectManagements;
            this.communicationTools = communicationTools;
            this.documentationTools = documentationTools;
            this.apiDevelopmentTools = apiDevelopmentTools;
            this.designTools = designTools;
            this.editors = editors;
            this.developmentEnvironments = developmentEnvironments;
        }

        /**
         * ファクトリーメソッド
         *
         * @param sourceControls          ソース管理
         * @param projectManagements      プロジェクト管理
         * @param communicationTools      コミュニケーション
         * @param documentationTools      ドキュメント
         * @param apiDevelopmentTools     API開発
         * @param designTools             デザイン
         * @param editors                 エディタ
         * @param developmentEnvironments 開発環境
         * @return 値オブジェクト
         */
        public static Tools create(List<String> sourceControls,
                List<String> projectManagements,
                List<String> communicationTools,
                List<String> documentationTools,
                List<String> apiDevelopmentTools,
                List<String> designTools,
                List<String> editors,
                List<String> developmentEnvironments) {
            return new Tools(sourceControls, projectManagements, communicationTools,
                    documentationTools, apiDevelopmentTools, designTools,
                    editors, developmentEnvironments);
        }
    }
}
