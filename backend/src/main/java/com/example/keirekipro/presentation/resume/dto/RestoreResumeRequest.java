package com.example.keirekipro.presentation.resume.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;
import java.util.function.Function;

import com.example.keirekipro.usecase.resume.command.RestoreResumeCommand;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 職務経歴書リストアリクエストDTO
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class RestoreResumeRequest {

    /**
     * バージョン
     */
    private String version;

    /**
     * エクスポート日時
     */
    private Instant exportedAt;

    /**
     * 職務経歴書データ
     */
    private ResumeDto resume;

    /**
     * ユースケースコマンドへ変換する
     *
     * @param userId ユーザーID
     * @return 職務経歴書復元コマンド
     */
    public RestoreResumeCommand toCommand(UUID userId) {
        return new RestoreResumeCommand(userId, version, toResumeCommand(resume));
    }

    private static RestoreResumeCommand.ResumeCommand toResumeCommand(ResumeDto src) {
        if (src == null) {
            return null;
        }
        return new RestoreResumeCommand.ResumeCommand(
                src.resumeName,
                src.date,
                src.lastName,
                src.firstName,
                map(src.careers, RestoreResumeRequest::toCareerCommand),
                map(src.projects, RestoreResumeRequest::toProjectCommand),
                map(src.certifications, RestoreResumeRequest::toCertificationCommand),
                map(src.portfolios, RestoreResumeRequest::toPortfolioCommand),
                map(src.snsPlatforms, RestoreResumeRequest::toSnsPlatformCommand),
                map(src.selfPromotions, RestoreResumeRequest::toSelfPromotionCommand));
    }

    private static RestoreResumeCommand.CareerCommand toCareerCommand(CareerDto src) {
        return new RestoreResumeCommand.CareerCommand(src.companyName, src.startDate, src.endDate, src.active);
    }

    private static RestoreResumeCommand.ProjectCommand toProjectCommand(ProjectDto src) {
        return new RestoreResumeCommand.ProjectCommand(
                src.companyName,
                src.startDate,
                src.endDate,
                src.active,
                src.name,
                src.overview,
                src.teamComp,
                src.role,
                src.achievement,
                toProcessCommand(src.process),
                toTechStackCommand(src.techStack));
    }

    private static RestoreResumeCommand.ProcessCommand toProcessCommand(ProcessDto src) {
        if (src == null) {
            return null;
        }
        return new RestoreResumeCommand.ProcessCommand(
                src.requirements,
                src.basicDesign,
                src.detailedDesign,
                src.implementation,
                src.integrationTest,
                src.systemTest,
                src.maintenance);
    }

    private static RestoreResumeCommand.TechStackCommand toTechStackCommand(TechStackDto src) {
        if (src == null) {
            return null;
        }
        return new RestoreResumeCommand.TechStackCommand(
                toFrontendCommand(src.frontend),
                toBackendCommand(src.backend),
                toInfrastructureCommand(src.infrastructure),
                toToolsCommand(src.tools));
    }

    private static RestoreResumeCommand.FrontendCommand toFrontendCommand(FrontendDto src) {
        if (src == null) {
            return null;
        }
        return new RestoreResumeCommand.FrontendCommand(
                src.languages,
                src.frameworks,
                src.libraries,
                src.buildTools,
                src.packageManagers,
                src.linters,
                src.formatters,
                src.testingTools);
    }

    private static RestoreResumeCommand.BackendCommand toBackendCommand(BackendDto src) {
        if (src == null) {
            return null;
        }
        return new RestoreResumeCommand.BackendCommand(
                src.languages,
                src.frameworks,
                src.libraries,
                src.buildTools,
                src.packageManagers,
                src.linters,
                src.formatters,
                src.testingTools,
                src.ormTools,
                src.auth);
    }

    private static RestoreResumeCommand.InfrastructureCommand toInfrastructureCommand(InfrastructureDto src) {
        if (src == null) {
            return null;
        }
        return new RestoreResumeCommand.InfrastructureCommand(
                src.clouds,
                src.operatingSystems,
                src.containers,
                src.databases,
                src.webServers,
                src.ciCdTools,
                src.iacTools,
                src.monitoringTools,
                src.loggingTools);
    }

    private static RestoreResumeCommand.ToolsCommand toToolsCommand(ToolsDto src) {
        if (src == null) {
            return null;
        }
        return new RestoreResumeCommand.ToolsCommand(
                src.sourceControls,
                src.projectManagements,
                src.communicationTools,
                src.documentationTools,
                src.apiDevelopmentTools,
                src.designTools,
                src.editors,
                src.developmentEnvironments);
    }

    private static RestoreResumeCommand.CertificationCommand toCertificationCommand(CertificationDto src) {
        return new RestoreResumeCommand.CertificationCommand(src.name, src.date);
    }

    private static RestoreResumeCommand.PortfolioCommand toPortfolioCommand(PortfolioDto src) {
        return new RestoreResumeCommand.PortfolioCommand(src.name, src.overview, src.techStack, src.link);
    }

    private static RestoreResumeCommand.SnsPlatformCommand toSnsPlatformCommand(SnsPlatformDto src) {
        return new RestoreResumeCommand.SnsPlatformCommand(src.name, src.link);
    }

    private static RestoreResumeCommand.SelfPromotionCommand toSelfPromotionCommand(SelfPromotionDto src) {
        return new RestoreResumeCommand.SelfPromotionCommand(src.title, src.content);
    }

    private static <T, R> List<R> map(List<T> source, Function<T, R> mapper) {
        return source == null ? null : source.stream().map(mapper).toList();
    }

    /**
     * 職務経歴書DTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class ResumeDto {
        private String resumeName;

        private LocalDate date;

        private String lastName;
        private String firstName;
        private List<CareerDto> careers;
        private List<ProjectDto> projects;
        private List<CertificationDto> certifications;
        private List<PortfolioDto> portfolios;
        private List<SnsPlatformDto> snsPlatforms;
        private List<SelfPromotionDto> selfPromotions;
    }

    /**
     * 職歴DTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class CareerDto {
        private String companyName;
        private YearMonth startDate;
        private YearMonth endDate;
        private boolean active;
    }

    /**
     * プロジェクトDTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class ProjectDto {
        private String companyName;
        private YearMonth startDate;
        private YearMonth endDate;
        private boolean active;
        private String name;
        private String overview;
        private String teamComp;
        private String role;
        private String achievement;
        private ProcessDto process;
        private TechStackDto techStack;
    }

    /**
     * 作業工程DTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class ProcessDto {
        private boolean requirements;
        private boolean basicDesign;
        private boolean detailedDesign;
        private boolean implementation;
        private boolean integrationTest;
        private boolean systemTest;
        private boolean maintenance;
    }

    /**
     * 技術スタックDTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class TechStackDto {
        private FrontendDto frontend;
        private BackendDto backend;
        private InfrastructureDto infrastructure;
        private ToolsDto tools;
    }

    /**
     * フロントエンドDTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class FrontendDto {
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
     * バックエンドDTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class BackendDto {
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
     * インフラDTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class InfrastructureDto {
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
     * 開発支援ツールDTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class ToolsDto {
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
     * 資格DTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class CertificationDto {
        private String name;
        private YearMonth date;
    }

    /**
     * ポートフォリオDTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class PortfolioDto {
        private String name;
        private String overview;
        private String techStack;
        private String link;
    }

    /**
     * SNSプラットフォームDTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class SnsPlatformDto {
        private String name;
        private String link;
    }

    /**
     * 自己PRDTO
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class SelfPromotionDto {
        private String title;
        private String content;
    }
}
