package com.example.keirekipro.usecase.resume.command;

import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * 職務経歴書復元ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class RestoreResumeCommand {

    private UUID userId;

    private String version;

    private ResumeCommand resume;

    /**
     * 復元する職務経歴書本体
     */
    @Data
    @AllArgsConstructor
    public static class ResumeCommand {

        private String resumeName;
        private LocalDate date;
        private String lastName;
        private String firstName;
        private List<CareerCommand> careers;
        private List<ProjectCommand> projects;
        private List<CertificationCommand> certifications;
        private List<PortfolioCommand> portfolios;
        private List<SnsPlatformCommand> snsPlatforms;
        private List<SelfPromotionCommand> selfPromotions;
    }

    /**
     * 復元する職歴
     */
    @Data
    @AllArgsConstructor
    public static class CareerCommand {

        private String companyName;
        private YearMonth startDate;
        private YearMonth endDate;
        private boolean active;
    }

    /**
     * 復元するプロジェクト
     */
    @Data
    @AllArgsConstructor
    public static class ProjectCommand {

        private String companyName;
        private YearMonth startDate;
        private YearMonth endDate;
        private boolean active;
        private String name;
        private String overview;
        private String teamComp;
        private String role;
        private String achievement;
        private ProcessCommand process;
        private TechStackCommand techStack;
    }

    /**
     * 復元するプロジェクト工程
     */
    @Data
    @AllArgsConstructor
    public static class ProcessCommand {

        private boolean requirements;
        private boolean basicDesign;
        private boolean detailedDesign;
        private boolean implementation;
        private boolean integrationTest;
        private boolean systemTest;
        private boolean maintenance;
    }

    /**
     * 復元するプロジェクト技術スタック
     */
    @Data
    @AllArgsConstructor
    public static class TechStackCommand {

        private FrontendCommand frontend;
        private BackendCommand backend;
        private InfrastructureCommand infrastructure;
        private ToolsCommand tools;
    }

    /**
     * 復元するフロントエンド技術スタック
     */
    @Data
    @AllArgsConstructor
    public static class FrontendCommand {

        private List<String> languages;
        private List<String> frameworks;
        private List<String> libraries;
        private List<String> buildTools;
        private List<String> packageManagers;
        private List<String> linters;
        private List<String> formatters;
        private List<String> testingTools;
    }

    /**
     * 復元するバックエンド技術スタック
     */
    @Data
    @AllArgsConstructor
    public static class BackendCommand {

        private List<String> languages;
        private List<String> frameworks;
        private List<String> libraries;
        private List<String> buildTools;
        private List<String> packageManagers;
        private List<String> linters;
        private List<String> formatters;
        private List<String> testingTools;
        private List<String> ormTools;
        private List<String> auth;
    }

    /**
     * 復元するインフラ技術スタック
     */
    @Data
    @AllArgsConstructor
    public static class InfrastructureCommand {

        private List<String> clouds;
        private List<String> operatingSystems;
        private List<String> containers;
        private List<String> databases;
        private List<String> webServers;
        private List<String> ciCdTools;
        private List<String> iacTools;
        private List<String> monitoringTools;
        private List<String> loggingTools;
    }

    /**
     * 復元するツール技術スタック
     */
    @Data
    @AllArgsConstructor
    public static class ToolsCommand {

        private List<String> sourceControls;
        private List<String> projectManagements;
        private List<String> communicationTools;
        private List<String> documentationTools;
        private List<String> apiDevelopmentTools;
        private List<String> designTools;
        private List<String> editors;
        private List<String> developmentEnvironments;
    }

    /**
     * 復元する資格
     */
    @Data
    @AllArgsConstructor
    public static class CertificationCommand {

        private String name;
        private YearMonth date;
    }

    /**
     * 復元するポートフォリオ
     */
    @Data
    @AllArgsConstructor
    public static class PortfolioCommand {

        private String name;
        private String overview;
        private String techStack;
        private String link;
    }

    /**
     * 復元するSNSプラットフォーム
     */
    @Data
    @AllArgsConstructor
    public static class SnsPlatformCommand {

        private String name;
        private String link;
    }

    /**
     * 復元する自己PR
     */
    @Data
    @AllArgsConstructor
    public static class SelfPromotionCommand {

        private String title;
        private String content;
    }
}
