package com.example.keirekipro.usecase.resume.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書バックアップ用ユースケースDTO
 */
@Getter
@Builder
@RequiredArgsConstructor
public class BackupResumeUseCaseDto {

    /**
     * ファイル名
     */
    private final String fileName;

    /**
     * Content-Type
     */
    private final String contentType;

    /**
     * バージョン
     */
    private final String version;

    /**
     * エクスポート日時
     */
    private final Instant exportedAt;

    /**
     * 職務経歴書データ
     */
    private final ResumeDto resume;

    /**
     * 職務経歴書DTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class ResumeDto {
        private final String resumeName;
        private final LocalDate date;
        private final String lastName;
        private final String firstName;
        private final List<CareerDto> careers;
        private final List<ProjectDto> projects;
        private final List<CertificationDto> certifications;
        private final List<PortfolioDto> portfolios;
        private final List<SnsPlatformDto> snsPlatforms;
        private final List<SelfPromotionDto> selfPromotions;
    }

    /**
     * 職歴DTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class CareerDto {
        private final String companyName;
        private final YearMonth startDate;
        private final YearMonth endDate;
        private final boolean active;
    }

    /**
     * プロジェクトDTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class ProjectDto {
        private final String companyName;
        private final YearMonth startDate;
        private final YearMonth endDate;
        private final boolean active;
        private final String name;
        private final String overview;
        private final String teamComp;
        private final String role;
        private final String achievement;
        private final ProcessDto process;
        private final TechStackDto techStack;
    }

    /**
     * 作業工程DTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class ProcessDto {
        private final boolean requirements;
        private final boolean basicDesign;
        private final boolean detailedDesign;
        private final boolean implementation;
        private final boolean integrationTest;
        private final boolean systemTest;
        private final boolean maintenance;
    }

    /**
     * 技術スタックDTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class TechStackDto {
        private final FrontendDto frontend;
        private final BackendDto backend;
        private final InfrastructureDto infrastructure;
        private final ToolsDto tools;
    }

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

    /**
     * 資格DTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class CertificationDto {
        private final String name;
        private final YearMonth date;
    }

    /**
     * ポートフォリオDTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class PortfolioDto {
        private final String name;
        private final String overview;
        private final String techStack;
        private final String link;
    }

    /**
     * SNSプラットフォームDTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class SnsPlatformDto {
        private final String name;
        private final String link;
    }

    /**
     * 自己PRDTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class SelfPromotionDto {
        private final String title;
        private final String content;
    }
}
