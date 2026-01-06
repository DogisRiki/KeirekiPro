package com.example.keirekipro.presentation.resume.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;

import com.example.keirekipro.usecase.resume.dto.BackupResumeUseCaseDto;
import com.fasterxml.jackson.annotation.JsonInclude;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書バックアップレスポンスDTO
 */
@Getter
@Builder
@RequiredArgsConstructor
public class BackupResumeResponse {

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
     * ユースケースDTOからレスポンスへの変換を行う
     *
     * @param useCaseDto ユースケースDTO
     * @return レスポンス
     */
    public static BackupResumeResponse convertToResponse(BackupResumeUseCaseDto useCaseDto) {
        return BackupResumeResponse.builder()
                .version(useCaseDto.getVersion())
                .exportedAt(useCaseDto.getExportedAt())
                .resume(convertResumeDto(useCaseDto.getResume()))
                .build();
    }

    /**
     * ResumeDto変換
     */
    private static ResumeDto convertResumeDto(BackupResumeUseCaseDto.ResumeDto dto) {
        return ResumeDto.builder()
                .resumeName(dto.getResumeName())
                .date(dto.getDate())
                .lastName(dto.getLastName())
                .firstName(dto.getFirstName())
                .careers(dto.getCareers().stream()
                        .map(c -> CareerDto.builder()
                                .companyName(c.getCompanyName())
                                .startDate(c.getStartDate())
                                .endDate(c.getEndDate())
                                .active(c.isActive())
                                .build())
                        .toList())
                .projects(dto.getProjects().stream()
                        .map(p -> ProjectDto.builder()
                                .companyName(p.getCompanyName())
                                .startDate(p.getStartDate())
                                .endDate(p.getEndDate())
                                .active(p.isActive())
                                .name(p.getName())
                                .overview(p.getOverview())
                                .teamComp(p.getTeamComp())
                                .role(p.getRole())
                                .achievement(p.getAchievement())
                                .process(ProcessDto.builder()
                                        .requirements(p.getProcess().isRequirements())
                                        .basicDesign(p.getProcess().isBasicDesign())
                                        .detailedDesign(p.getProcess().isDetailedDesign())
                                        .implementation(p.getProcess().isImplementation())
                                        .integrationTest(p.getProcess().isIntegrationTest())
                                        .systemTest(p.getProcess().isSystemTest())
                                        .maintenance(p.getProcess().isMaintenance())
                                        .build())
                                .techStack(TechStackDto.builder()
                                        .frontend(FrontendDto.builder()
                                                .languages(p.getTechStack().getFrontend().getLanguages())
                                                .frameworks(p.getTechStack().getFrontend().getFrameworks())
                                                .libraries(p.getTechStack().getFrontend().getLibraries())
                                                .buildTools(p.getTechStack().getFrontend().getBuildTools())
                                                .packageManagers(p.getTechStack().getFrontend().getPackageManagers())
                                                .linters(p.getTechStack().getFrontend().getLinters())
                                                .formatters(p.getTechStack().getFrontend().getFormatters())
                                                .testingTools(p.getTechStack().getFrontend().getTestingTools())
                                                .build())
                                        .backend(BackendDto.builder()
                                                .languages(p.getTechStack().getBackend().getLanguages())
                                                .frameworks(p.getTechStack().getBackend().getFrameworks())
                                                .libraries(p.getTechStack().getBackend().getLibraries())
                                                .buildTools(p.getTechStack().getBackend().getBuildTools())
                                                .packageManagers(p.getTechStack().getBackend().getPackageManagers())
                                                .linters(p.getTechStack().getBackend().getLinters())
                                                .formatters(p.getTechStack().getBackend().getFormatters())
                                                .testingTools(p.getTechStack().getBackend().getTestingTools())
                                                .ormTools(p.getTechStack().getBackend().getOrmTools())
                                                .auth(p.getTechStack().getBackend().getAuth())
                                                .build())
                                        .infrastructure(InfrastructureDto.builder()
                                                .clouds(p.getTechStack().getInfrastructure().getClouds())
                                                .operatingSystems(
                                                        p.getTechStack().getInfrastructure().getOperatingSystems())
                                                .containers(p.getTechStack().getInfrastructure().getContainers())
                                                .databases(p.getTechStack().getInfrastructure().getDatabases())
                                                .webServers(p.getTechStack().getInfrastructure().getWebServers())
                                                .ciCdTools(p.getTechStack().getInfrastructure().getCiCdTools())
                                                .iacTools(p.getTechStack().getInfrastructure().getIacTools())
                                                .monitoringTools(
                                                        p.getTechStack().getInfrastructure().getMonitoringTools())
                                                .loggingTools(p.getTechStack().getInfrastructure().getLoggingTools())
                                                .build())
                                        .tools(ToolsDto.builder()
                                                .sourceControls(p.getTechStack().getTools().getSourceControls())
                                                .projectManagements(
                                                        p.getTechStack().getTools().getProjectManagements())
                                                .communicationTools(
                                                        p.getTechStack().getTools().getCommunicationTools())
                                                .documentationTools(
                                                        p.getTechStack().getTools().getDocumentationTools())
                                                .apiDevelopmentTools(
                                                        p.getTechStack().getTools().getApiDevelopmentTools())
                                                .designTools(p.getTechStack().getTools().getDesignTools())
                                                .editors(p.getTechStack().getTools().getEditors())
                                                .developmentEnvironments(
                                                        p.getTechStack().getTools().getDevelopmentEnvironments())
                                                .build())
                                        .build())
                                .build())
                        .toList())
                .certifications(dto.getCertifications().stream()
                        .map(c -> CertificationDto.builder()
                                .name(c.getName())
                                .date(c.getDate())
                                .build())
                        .toList())
                .portfolios(dto.getPortfolios().stream()
                        .map(pf -> PortfolioDto.builder()
                                .name(pf.getName())
                                .overview(pf.getOverview())
                                .techStack(pf.getTechStack())
                                .link(pf.getLink())
                                .build())
                        .toList())
                .snsPlatforms(dto.getSnsPlatforms().stream()
                        .map(sp -> SnsPlatformDto.builder()
                                .name(sp.getName())
                                .link(sp.getLink())
                                .build())
                        .toList())
                .selfPromotions(dto.getSelfPromotions().stream()
                        .map(sp -> SelfPromotionDto.builder()
                                .title(sp.getTitle())
                                .content(sp.getContent())
                                .build())
                        .toList())
                .build();
    }

    /**
     * 職務経歴書DTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class ResumeDto {
        private final String resumeName;
        private final LocalDate date;

        @JsonInclude(JsonInclude.Include.NON_NULL)
        private final String lastName;

        @JsonInclude(JsonInclude.Include.NON_NULL)
        private final String firstName;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<CareerDto> careers;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<ProjectDto> projects;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<CertificationDto> certifications;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<PortfolioDto> portfolios;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<SnsPlatformDto> snsPlatforms;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
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

        @JsonInclude(JsonInclude.Include.NON_NULL)
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

        @JsonInclude(JsonInclude.Include.NON_NULL)
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
        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> languages;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> frameworks;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> libraries;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> buildTools;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> packageManagers;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> linters;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> formatters;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> testingTools;
    }

    /**
     * バックエンドDTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class BackendDto {
        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> languages;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> frameworks;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> libraries;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> buildTools;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> packageManagers;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> linters;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> formatters;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> testingTools;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> ormTools;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> auth;
    }

    /**
     * インフラDTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class InfrastructureDto {
        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> clouds;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> operatingSystems;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> containers;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> databases;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> webServers;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> ciCdTools;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> iacTools;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> monitoringTools;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> loggingTools;
    }

    /**
     * 開発支援ツールDTO
     */
    @Getter
    @Builder
    @RequiredArgsConstructor
    public static class ToolsDto {
        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> sourceControls;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> projectManagements;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> communicationTools;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> documentationTools;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> apiDevelopmentTools;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> designTools;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        private final List<String> editors;

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
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

        @JsonInclude(JsonInclude.Include.NON_NULL)
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
