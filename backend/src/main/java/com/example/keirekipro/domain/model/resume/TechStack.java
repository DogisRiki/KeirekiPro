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
     * 開発言語
     */
    private final List<String> languages;

    /**
     * 依存関係
     */
    private final Dependencies dependencies;

    /**
     * インフラ
     */
    private final Infrastructure infrastructure;

    /**
     * 開発支援ツール
     */
    private final Tools tools;

    private TechStack(List<String> languages, Dependencies dependencies, Infrastructure infrastructure, Tools tools) {
        this.languages = languages;
        this.dependencies = dependencies;
        this.infrastructure = infrastructure;
        this.tools = tools;
    }

    /**
     * ファクトリーメソッド
     *
     * @param languages      開発言語
     * @param dependencies   依存関係
     * @param infrastructure インフラ
     * @param tools          開発支援ツール
     * @return 値オブジェクト
     */
    public static TechStack create(List<String> languages, Dependencies dependencies, Infrastructure infrastructure,
            Tools tools) {
        return new TechStack(languages, dependencies, infrastructure, tools);
    }

    /**
     * 依存関係
     */
    @Getter
    @EqualsAndHashCode
    public static class Dependencies {

        /**
         * フレームワーク
         */
        private final List<String> frameworks;

        /**
         * ライブラリ
         */
        private final List<String> libraries;

        /**
         * テスト
         */
        private final List<String> testingTools;

        /**
         * ORM
         */
        private final List<String> ormTools;

        /**
         * パッケージマネージャー
         */
        private final List<String> packageManagers;

        private Dependencies(List<String> frameworks, List<String> libraries, List<String> testingTools,
                List<String> ormTools, List<String> packageManagers) {
            this.frameworks = frameworks;
            this.libraries = libraries;
            this.testingTools = testingTools;
            this.ormTools = ormTools;
            this.packageManagers = packageManagers;
        }

        /**
         * ファクトリーメソッド
         *
         * @param frameworks      フレームワーク
         * @param libraries       ライブラリ
         * @param testingTools    テスト
         * @param ormTools        ORM
         * @param packageManagers パッケージマネージャー
         * @return 値オブジェクト
         */
        public static Dependencies create(List<String> frameworks, List<String> libraries, List<String> testingTools,
                List<String> ormTools, List<String> packageManagers) {
            return new Dependencies(frameworks, libraries, testingTools, ormTools, packageManagers);
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
         * コンテナ
         */
        private final List<String> containers;

        /**
         * データベース
         */
        private final List<String> databases;

        /**
         * ウェブサーバー
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

        private Infrastructure(List<String> clouds, List<String> containers, List<String> databases,
                List<String> webServers,
                List<String> ciCdTools, List<String> iacTools, List<String> monitoringTools,
                List<String> loggingTools) {
            this.clouds = clouds;
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
         * @param clouds          クラウド
         * @param containers      コンテナ
         * @param databases       データベース
         * @param webServers      ウェブサーバー
         * @param ciCdTools       CI/CD
         * @param iacTools        IaC
         * @param monitoringTools 監視
         * @param loggingTools    ロギング
         * @return 値オブジェクト
         */
        public static Infrastructure create(List<String> clouds, List<String> containers, List<String> databases,
                List<String> webServers,
                List<String> ciCdTools, List<String> iacTools, List<String> monitoringTools,
                List<String> loggingTools) {
            return new Infrastructure(clouds, containers, databases, webServers, ciCdTools, iacTools, monitoringTools,
                    loggingTools);
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

        private Tools(List<String> sourceControls, List<String> projectManagements, List<String> communicationTools,
                List<String> documentationTools, List<String> apiDevelopmentTools, List<String> designTools) {
            this.sourceControls = sourceControls;
            this.projectManagements = projectManagements;
            this.communicationTools = communicationTools;
            this.documentationTools = documentationTools;
            this.apiDevelopmentTools = apiDevelopmentTools;
            this.designTools = designTools;
        }

        /**
         * ファクトリーメソッド
         *
         * @param sourceControls      ソース管理
         * @param projectManagements  プロジェクト管理
         * @param communicationTools  コミュニケーション
         * @param documentationTools  ドキュメント
         * @param apiDevelopmentTools API開発
         * @param designTools         デザイン
         * @return 値オブジェクト
         */
        public static Tools create(List<String> sourceControls, List<String> projectManagements,
                List<String> communicationTools,
                List<String> documentationTools, List<String> apiDevelopmentTools, List<String> designTools) {
            return new Tools(sourceControls, projectManagements, communicationTools, documentationTools,
                    apiDevelopmentTools, designTools);
        }
    }
}
