package com.example.keirekipro.usecase.query.techstack.dto;

import java.util.List;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * 技術スタック一覧クエリDTO
 */
@Getter
@Builder
@RequiredArgsConstructor
public class TechStackListQueryDto {

    private final FrontendDto frontend;
    private final BackendDto backend;
    private final InfrastructureDto infrastructure;
    private final ToolsDto tools;

    /**
     * フロントエンドDTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class FrontendDto {
        private final List<String> languages;
        private final List<String> frameworks;
        private final List<String> libraries;
        private final List<String> buildTools;
        private final List<String> packageManagers;
        private final List<String> linters;
        private final List<String> formatters;
        private final List<String> testingTools;
    }

    /**
     * バックエンドDTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class BackendDto {
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
    }

    /**
     * インフラDTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class InfrastructureDto {
        private final List<String> clouds;
        private final List<String> operatingSystems;
        private final List<String> containers;
        private final List<String> databases;
        private final List<String> webServers;
        private final List<String> ciCdTools;
        private final List<String> iacTools;
        private final List<String> monitoringTools;
        private final List<String> loggingTools;
    }

    /**
     * 開発支援ツールDTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class ToolsDto {
        private final List<String> sourceControls;
        private final List<String> projectManagements;
        private final List<String> communicationTools;
        private final List<String> documentationTools;
        private final List<String> apiDevelopmentTools;
        private final List<String> designTools;
        private final List<String> editors;
        private final List<String> developmentEnvironments;
    }
}
