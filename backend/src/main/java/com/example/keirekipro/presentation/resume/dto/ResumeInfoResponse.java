package com.example.keirekipro.presentation.resume.dto;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.List;
import java.util.stream.Collectors;

import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.fasterxml.jackson.annotation.JsonInclude;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;

/**
 * 職務経歴書情報レスポンスDTO
 */
@Getter
@Builder
@AllArgsConstructor
public class ResumeInfoResponse {

    private final String id;

    private final String resumeName;

    private final LocalDate date;

    @JsonInclude(JsonInclude.Include.NON_NULL)
    private final String lastName;

    @JsonInclude(JsonInclude.Include.NON_NULL)
    private final String firstName;

    private final LocalDateTime createdAt;

    private final LocalDateTime updatedAt;

    @JsonInclude(JsonInclude.Include.NON_EMPTY)
    private final List<CareerResponse> careers;

    @JsonInclude(JsonInclude.Include.NON_EMPTY)
    private final List<ProjectResponse> projects;

    @JsonInclude(JsonInclude.Include.NON_EMPTY)
    private final List<CertificationResponse> certifications;

    @JsonInclude(JsonInclude.Include.NON_EMPTY)
    private final List<PortfolioResponse> portfolios;

    @JsonInclude(JsonInclude.Include.NON_EMPTY)
    private final List<SocialLinkResponse> socialLinks;

    @JsonInclude(JsonInclude.Include.NON_EMPTY)
    private final List<SelfPromotionResponse> selfPromotions;

    /**
     * ユースケースDTOからレスポンスへの変換を行う
     *
     * @param dto 職務経歴書ユースケースDTO
     * @return 職務経歴書情報レスポンス
     */
    public static ResumeInfoResponse convertToResponse(ResumeInfoUseCaseDto dto) {
        return ResumeInfoResponse.builder()
                .id(dto.getId().toString())
                .resumeName(dto.getResumeName())
                .date(dto.getDate())
                .lastName(dto.getLastName())
                .firstName(dto.getFirstName())
                .createdAt(dto.getCreatedAt())
                .updatedAt(dto.getUpdatedAt())
                .careers(dto.getCareers().stream()
                        .map(c -> new CareerResponse(
                                c.getId().toString(),
                                c.getCompanyName(),
                                c.getStartDate(),
                                c.getEndDate(),
                                c.isActive()))
                        .collect(Collectors.toList()))
                .projects(dto.getProjects().stream()
                        .map(p -> {
                            ResumeInfoUseCaseDto.TechStackDto tech = p.getTechStack();
                            ResumeInfoUseCaseDto.FrontendDto frontend = tech.getFrontend();
                            ResumeInfoUseCaseDto.BackendDto backend = tech.getBackend();
                            ResumeInfoUseCaseDto.InfrastructureDto infra = tech.getInfrastructure();
                            ResumeInfoUseCaseDto.ToolsDto tools = tech.getTools();

                            return new ProjectResponse(
                                    p.getId().toString(),
                                    p.getCompanyName(),
                                    p.getStartDate(),
                                    p.getEndDate(),
                                    p.isActive(),
                                    p.getName(),
                                    p.getOverview(),
                                    p.getTeamComp(),
                                    p.getRole(),
                                    p.getAchievement(),
                                    new ProcessResponse(
                                            p.getProcess().isRequirements(),
                                            p.getProcess().isBasicDesign(),
                                            p.getProcess().isDetailedDesign(),
                                            p.getProcess().isImplementation(),
                                            p.getProcess().isIntegrationTest(),
                                            p.getProcess().isSystemTest(),
                                            p.getProcess().isMaintenance()),
                                    new TechStackResponse(
                                            new FrontendResponse(
                                                    frontend.getLanguages(),
                                                    frontend.getFrameworks(),
                                                    frontend.getLibraries(),
                                                    frontend.getBuildTools(),
                                                    frontend.getPackageManagers(),
                                                    frontend.getLinters(),
                                                    frontend.getFormatters(),
                                                    frontend.getTestingTools()),
                                            new BackendResponse(
                                                    backend.getLanguages(),
                                                    backend.getFrameworks(),
                                                    backend.getLibraries(),
                                                    backend.getBuildTools(),
                                                    backend.getPackageManagers(),
                                                    backend.getLinters(),
                                                    backend.getFormatters(),
                                                    backend.getTestingTools(),
                                                    backend.getOrmTools(),
                                                    backend.getAuth()),
                                            new InfrastructureResponse(
                                                    infra.getClouds(),
                                                    infra.getOperatingSystems(),
                                                    infra.getContainers(),
                                                    infra.getDatabases(),
                                                    infra.getWebServers(),
                                                    infra.getCiCdTools(),
                                                    infra.getIacTools(),
                                                    infra.getMonitoringTools(),
                                                    infra.getLoggingTools()),
                                            new ToolsResponse(
                                                    tools.getSourceControls(),
                                                    tools.getProjectManagements(),
                                                    tools.getCommunicationTools(),
                                                    tools.getDocumentationTools(),
                                                    tools.getApiDevelopmentTools(),
                                                    tools.getDesignTools(),
                                                    tools.getEditors(),
                                                    tools.getDevelopmentEnvironments())));
                        })
                        .collect(Collectors.toList()))
                .certifications(dto.getCertifications().stream()
                        .map(c -> new CertificationResponse(
                                c.getId().toString(),
                                c.getName(),
                                c.getDate()))
                        .collect(Collectors.toList()))
                .portfolios(dto.getPortfolios().stream()
                        .map(pf -> new PortfolioResponse(
                                pf.getId().toString(),
                                pf.getName(),
                                pf.getOverview(),
                                pf.getTechStack(),
                                pf.getLink()))
                        .collect(Collectors.toList()))
                .socialLinks(dto.getSocialLinks().stream()
                        .map(sl -> new SocialLinkResponse(
                                sl.getId().toString(),
                                sl.getName(),
                                sl.getLink()))
                        .collect(Collectors.toList()))
                .selfPromotions(dto.getSelfPromotions().stream()
                        .map(sp -> new SelfPromotionResponse(
                                sp.getId().toString(),
                                sp.getTitle(),
                                sp.getContent()))
                        .collect(Collectors.toList()))
                .build();
    }

    /**
     * 職歴
     */
    @Getter
    @AllArgsConstructor
    public static class CareerResponse {
        private final String id;
        private final String companyName;
        private final YearMonth startDate;
        private final YearMonth endDate;
        private final boolean active;
    }

    /**
     * プロジェクト
     */
    @Getter
    @AllArgsConstructor
    public static class ProjectResponse {
        private final String id;
        private final String companyName;
        private final YearMonth startDate;
        private final YearMonth endDate;
        private final boolean active;
        private final String name;
        private final String overview;
        private final String teamComp;
        private final String role;
        private final String achievement;
        private final ProcessResponse process;
        private final TechStackResponse techStack;
    }

    /**
     * 作業工程
     */
    @Getter
    @AllArgsConstructor
    public static class ProcessResponse {
        private final boolean requirements;
        private final boolean basicDesign;
        private final boolean detailedDesign;
        private final boolean implementation;
        private final boolean integrationTest;
        private final boolean maintenance;
        private final boolean systemTest;
    }

    /**
     * 技術スタック
     */
    @Getter
    @AllArgsConstructor
    public static class TechStackResponse {
        private final FrontendResponse frontend;
        private final BackendResponse backend;
        private final InfrastructureResponse infrastructure;
        private final ToolsResponse tools;
    }

    /**
     * フロントエンド
     */
    @Getter
    @AllArgsConstructor
    public static class FrontendResponse {
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
     * バックエンド
     */
    @Getter
    @AllArgsConstructor
    public static class BackendResponse {
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
     * インフラ
     */
    @Getter
    @AllArgsConstructor
    public static class InfrastructureResponse {
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
     * 開発支援ツール
     */
    @Getter
    @AllArgsConstructor
    public static class ToolsResponse {
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
     * 資格
     */
    @Getter
    @AllArgsConstructor
    public static class CertificationResponse {
        private final String id;
        private final String name;
        private final YearMonth date;
    }

    /**
     * ポートフォリオ
     */
    @Getter
    @AllArgsConstructor
    public static class PortfolioResponse {
        private final String id;
        private final String name;
        private final String overview;
        private final String techStack;
        private final String link;
    }

    /**
     * ソーシャルリンク
     */
    @Getter
    @AllArgsConstructor
    public static class SocialLinkResponse {
        private final String id;
        private final String name;
        private final String link;
    }

    /**
     * 自己PR
     */
    @Getter
    @AllArgsConstructor
    public static class SelfPromotionResponse {
        private final String id;
        private final String title;
        private final String content;
    }
}
