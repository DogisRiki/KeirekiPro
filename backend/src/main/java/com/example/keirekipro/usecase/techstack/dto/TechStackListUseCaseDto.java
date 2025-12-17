package com.example.keirekipro.usecase.techstack.dto;

import java.util.List;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * 技術スタック一覧ユースケースDTO
 *
 * 画面入力補助用のマスタ一覧を表現するQueryモデル
 */
@Getter
@EqualsAndHashCode
public class TechStackListUseCaseDto {

    private final Frontend frontend;
    private final Backend backend;
    private final Infrastructure infrastructure;
    private final Tools tools;

    private TechStackListUseCaseDto(Frontend frontend,
            Backend backend,
            Infrastructure infrastructure,
            Tools tools) {
        this.frontend = frontend;
        this.backend = backend;
        this.infrastructure = infrastructure;
        this.tools = tools;
    }

    /**
     * ファクトリーメソッド
     */
    public static TechStackListUseCaseDto create(Frontend frontend,
            Backend backend,
            Infrastructure infrastructure,
            Tools tools) {
        return new TechStackListUseCaseDto(frontend, backend, infrastructure, tools);
    }

    /**
     * フロントエンド
     */
    @Getter
    @EqualsAndHashCode
    public static class Frontend {

        private final List<String> languages;
        private final List<String> frameworks;
        private final List<String> libraries;
        private final List<String> buildTools;
        private final List<String> packageManagers;
        private final List<String> linters;
        private final List<String> formatters;
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
         * フロントエンドファクトリーメソッド
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
     * バックエンド
     */
    @Getter
    @EqualsAndHashCode
    public static class Backend {

        private final List<String> languages;
        private final List<String> frameworks;
        private final List<String> libraries;
        private final List<String> buildTools;
        private final List<String> packageManagers;
        private final List<String> linters;
        private final List<String> formatters;
        private final List<String> testingTools;
        private final List<String> ormTools;
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
         * バックエンドファクトリーメソッド
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

        private final List<String> clouds;
        private final List<String> operatingSystems;
        private final List<String> containers;
        private final List<String> databases;
        private final List<String> webServers;
        private final List<String> ciCdTools;
        private final List<String> iacTools;
        private final List<String> monitoringTools;
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
         * インフラファクトリーメソッド
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
            return new Infrastructure(clouds, operatingSystems, containers,
                    databases, webServers, ciCdTools, iacTools,
                    monitoringTools, loggingTools);
        }
    }

    /**
     * 開発支援ツール
     */
    @Getter
    @EqualsAndHashCode
    public static class Tools {

        private final List<String> sourceControls;
        private final List<String> projectManagements;
        private final List<String> communicationTools;
        private final List<String> documentationTools;
        private final List<String> apiDevelopmentTools;
        private final List<String> designTools;
        private final List<String> editors;
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
         * 開発支援ツールファクトリーメソッド
         */
        public static Tools create(List<String> sourceControls,
                List<String> projectManagements,
                List<String> communicationTools,
                List<String> documentationTools,
                List<String> apiDevelopmentTools,
                List<String> designTools,
                List<String> editors,
                List<String> developmentEnvironments) {
            return new Tools(sourceControls, projectManagements,
                    communicationTools, documentationTools,
                    apiDevelopmentTools, designTools,
                    editors, developmentEnvironments);
        }
    }
}
