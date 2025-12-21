package com.example.keirekipro.presentation.techstack.dto;

import java.util.List;

import com.example.keirekipro.usecase.techstack.dto.TechStackListUseCaseDto;

import lombok.AccessLevel;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * 技術スタック一覧レスポンス
 */
@Getter
@EqualsAndHashCode
@RequiredArgsConstructor(access = AccessLevel.PRIVATE)
public class TechStackListResponse {

    private final Frontend frontend;
    private final Backend backend;
    private final Infrastructure infrastructure;
    private final Tools tools;

    /**
     * ユースケースDTOからレスポンスDTOへ変換する
     *
     * @param dto ユースケースDTO
     * @return レスポンスDTO
     */
    public static TechStackListResponse convertFrom(TechStackListUseCaseDto dto) {
        return new TechStackListResponse(
                Frontend.convertFrom(dto.getFrontend()),
                Backend.convertFrom(dto.getBackend()),
                Infrastructure.convertFrom(dto.getInfrastructure()),
                Tools.convertFrom(dto.getTools()));
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
         * フロントエンド変換
         */
        public static Frontend convertFrom(TechStackListUseCaseDto.Frontend src) {
            return new Frontend(
                    src.getLanguages(),
                    src.getFrameworks(),
                    src.getLibraries(),
                    src.getBuildTools(),
                    src.getPackageManagers(),
                    src.getLinters(),
                    src.getFormatters(),
                    src.getTestingTools());
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
         * バックエンド変換
         */
        public static Backend convertFrom(TechStackListUseCaseDto.Backend src) {
            return new Backend(
                    src.getLanguages(),
                    src.getFrameworks(),
                    src.getLibraries(),
                    src.getBuildTools(),
                    src.getPackageManagers(),
                    src.getLinters(),
                    src.getFormatters(),
                    src.getTestingTools(),
                    src.getOrmTools(),
                    src.getAuth());
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
         * インフラ変換
         */
        public static Infrastructure convertFrom(TechStackListUseCaseDto.Infrastructure src) {
            return new Infrastructure(
                    src.getClouds(),
                    src.getOperatingSystems(),
                    src.getContainers(),
                    src.getDatabases(),
                    src.getWebServers(),
                    src.getCiCdTools(),
                    src.getIacTools(),
                    src.getMonitoringTools(),
                    src.getLoggingTools());
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
         * 開発支援ツール変換
         */
        public static Tools convertFrom(TechStackListUseCaseDto.Tools src) {
            return new Tools(
                    src.getSourceControls(),
                    src.getProjectManagements(),
                    src.getCommunicationTools(),
                    src.getDocumentationTools(),
                    src.getApiDevelopmentTools(),
                    src.getDesignTools(),
                    src.getEditors(),
                    src.getDevelopmentEnvironments());
        }
    }
}
