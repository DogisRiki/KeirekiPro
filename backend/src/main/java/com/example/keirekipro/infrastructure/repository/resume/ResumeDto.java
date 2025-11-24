package com.example.keirekipro.infrastructure.repository.resume;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import lombok.Data;

/**
 * 職務経歴書DTO
 */
@Data
public class ResumeDto {

    private UUID id;
    private UUID userId;
    private String name;
    private LocalDate date;
    private String lastName;
    private String firstName;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
    private List<CareerDto> careers;
    private List<ProjectDto> projects;
    private List<CertificationDto> certifications;
    private List<PortfolioDto> portfolios;
    private List<SocialLinkDto> socialLinks;
    private List<SelfPromotionDto> selfPromotions;

    /**
     * 職歴
     */
    @Data
    public static class CareerDto {
        private UUID id;
        private UUID resumeId;
        private String companyName;
        private YearMonth startDate;
        private YearMonth endDate;
        private Boolean isActive;
    }

    /**
     * プロジェクト
     */
    @Data
    public static class ProjectDto {
        private UUID id;
        private UUID resumeId;
        private String companyName;
        private YearMonth startDate;
        private YearMonth endDate;
        private Boolean isActive;
        private String name;
        private String overview;
        private String teamComp;
        private String role;
        private String achievement;

        // Process
        private Boolean requirements;
        private Boolean basicDesign;
        private Boolean detailedDesign;
        private Boolean implementation;
        private Boolean integrationTest;
        private Boolean systemTest;
        private Boolean maintenance;

        // TechStack - Frontend
        private List<String> frontendLanguages;
        private String frontendFramework;
        private List<String> frontendLibraries;
        private String frontendBuildTool;
        private String frontendPackageManager;
        private List<String> frontendLinters;
        private List<String> frontendFormatters;
        private List<String> frontendTestingTools;

        // TechStack - Backend
        private List<String> backendLanguages;
        private String backendFramework;
        private List<String> backendLibraries;
        private String backendBuildTool;
        private String backendPackageManager;
        private List<String> backendLinters;
        private List<String> backendFormatters;
        private List<String> backendTestingTools;
        private List<String> ormTools;
        private List<String> auth;

        // TechStack - Infrastructure
        private List<String> clouds;
        private String operatingSystem;
        private List<String> containers;
        private String database;
        private String webServer;
        private String ciCdTool;
        private List<String> iacTools;
        private List<String> monitoringTools;
        private List<String> loggingTools;

        // TechStack - Tools
        private String sourceControl;
        private String projectManagement;
        private String communicationTool;
        private List<String> documentationTools;
        private List<String> apiDevelopmentTools;
        private List<String> designTools;
        private String editor;
        private String developmentEnvironment;
    }

    /**
     * 資格
     */
    @Data
    public static class CertificationDto {
        private UUID id;
        private UUID resumeId;
        private String name;
        private YearMonth date;
    }

    /**
     * ポートフォリオ
     */
    @Data
    public static class PortfolioDto {
        private UUID id;
        private UUID resumeId;
        private String name;
        private String overview;
        private String techStack;
        private String link;
    }

    /**
     * ソーシャルリンク
     */
    @Data
    public static class SocialLinkDto {
        private UUID id;
        private UUID resumeId;
        private String name;
        private String link;
    }

    /**
     * 自己PR
     */
    @Data
    public static class SelfPromotionDto {
        private UUID id;
        private UUID resumeId;
        private String title;
        private String content;
    }
}
