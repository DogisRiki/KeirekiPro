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

        // TechStack
        private List<String> languages;

        // TechStack - Dependencies
        private List<String> frameworks;
        private List<String> libraries;
        private List<String> testingTools;
        private List<String> ormTools;
        private List<String> packageManagers;

        // TechStack - Infrastructure
        private List<String> clouds;
        private List<String> containers;
        private List<String> databases;
        private List<String> webServers;
        private List<String> ciCdTools;
        private List<String> iacTools;
        private List<String> monitoringTools;
        private List<String> loggingTools;

        // TechStack - Tools
        private List<String> sourceControls;
        private List<String> projectManagements;
        private List<String> communicationTools;
        private List<String> documentationTools;
        private List<String> apiDevelopmentTools;
        private List<String> designTools;
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
