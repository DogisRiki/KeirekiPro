package com.example.keirekipro.usecase.resume.dto;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.TechStack;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書情報ユースケースDTO
 */
@Getter
@Builder
@RequiredArgsConstructor
public class ResumeInfoUseCaseDto {

    private final UUID id;
    private final String resumeName;
    private final LocalDate date;
    private final String lastName;
    private final String firstName;
    private final LocalDateTime createdAt;
    private final LocalDateTime updatedAt;
    private final List<Career> careers;
    private final List<Project> projects;
    private final List<Certification> certifications;
    private final List<Portfolio> portfolios;
    private final List<SocialLink> socialLinks;
    private final List<SelfPromotion> selfPromotions;

    /**
     * ドメインモデルからユースケースDTOへの変換を行う
     *
     * @param resume Resumeエンティティ
     * @return ユースケースDTO
     */
    public static ResumeInfoUseCaseDto convertToUseCaseDto(Resume resume) {
        return ResumeInfoUseCaseDto.builder()
                .id(resume.getId())
                .resumeName(resume.getName().getValue())
                .date(resume.getDate())
                .lastName(resume.getFullName() != null ? resume.getFullName().getLastName() : null)
                .firstName(resume.getFullName() != null ? resume.getFullName().getFirstName() : null)
                .createdAt(resume.getCreatedAt())
                .updatedAt(resume.getUpdatedAt())
                .careers(resume.getCareers().stream()
                        .map(c -> new Career(
                                c.getId(),
                                c.getCompanyName().getValue(),
                                c.getPeriod().getStartDate(),
                                c.getPeriod().getEndDate(),
                                c.getPeriod().isActive()))
                        .toList())
                .projects(resume.getProjects().stream()
                        .map(p -> {
                            TechStack domainTechStack = p.getTechStack();
                            TechStack.Frontend domainFrontend = domainTechStack.getFrontend();
                            TechStack.Backend domainBackend = domainTechStack.getBackend();
                            TechStack.Infrastructure domainInfrastructure = domainTechStack.getInfrastructure();
                            TechStack.Tools domainTools = domainTechStack.getTools();

                            return new Project(
                                    p.getId(),
                                    p.getCompanyName().getValue(),
                                    p.getPeriod().getStartDate(),
                                    p.getPeriod().getEndDate(),
                                    p.getPeriod().isActive(),
                                    p.getName(),
                                    p.getOverview(),
                                    p.getTeamComp(),
                                    p.getRole(),
                                    p.getAchievement(),
                                    new Process(
                                            p.getProcess().isRequirements(),
                                            p.getProcess().isBasicDesign(),
                                            p.getProcess().isDetailedDesign(),
                                            p.getProcess().isImplementation(),
                                            p.getProcess().isIntegrationTest(),
                                            p.getProcess().isSystemTest(),
                                            p.getProcess().isMaintenance()),
                                    new TechStackDto(
                                            new FrontendDto(
                                                    domainFrontend.getLanguages(),
                                                    domainFrontend.getFrameworks(),
                                                    domainFrontend.getLibraries(),
                                                    domainFrontend.getBuildTools(),
                                                    domainFrontend.getPackageManagers(),
                                                    domainFrontend.getLinters(),
                                                    domainFrontend.getFormatters(),
                                                    domainFrontend.getTestingTools()),
                                            new BackendDto(
                                                    domainBackend.getLanguages(),
                                                    domainBackend.getFrameworks(),
                                                    domainBackend.getLibraries(),
                                                    domainBackend.getBuildTools(),
                                                    domainBackend.getPackageManagers(),
                                                    domainBackend.getLinters(),
                                                    domainBackend.getFormatters(),
                                                    domainBackend.getTestingTools(),
                                                    domainBackend.getOrmTools(),
                                                    domainBackend.getAuth()),
                                            new InfrastructureDto(
                                                    domainInfrastructure.getClouds(),
                                                    domainInfrastructure.getOperatingSystems(),
                                                    domainInfrastructure.getContainers(),
                                                    domainInfrastructure.getDatabases(),
                                                    domainInfrastructure.getWebServers(),
                                                    domainInfrastructure.getCiCdTools(),
                                                    domainInfrastructure.getIacTools(),
                                                    domainInfrastructure.getMonitoringTools(),
                                                    domainInfrastructure.getLoggingTools()),
                                            new ToolsDto(
                                                    domainTools.getSourceControls(),
                                                    domainTools.getProjectManagements(),
                                                    domainTools.getCommunicationTools(),
                                                    domainTools.getDocumentationTools(),
                                                    domainTools.getApiDevelopmentTools(),
                                                    domainTools.getDesignTools(),
                                                    domainTools.getEditors(),
                                                    domainTools.getDevelopmentEnvironments())));
                        })
                        .toList())
                .certifications(resume.getCertifications().stream()
                        .map(c -> new Certification(
                                c.getId(),
                                c.getName(),
                                c.getDate()))
                        .toList())
                .portfolios(resume.getPortfolios().stream()
                        .map(pf -> new Portfolio(
                                pf.getId(),
                                pf.getName(),
                                pf.getOverview(),
                                pf.getTechStack(),
                                pf.getLink().getValue()))
                        .toList())
                .socialLinks(resume.getSocialLinks().stream()
                        .map(sl -> new SocialLink(
                                sl.getId(),
                                sl.getName(),
                                sl.getLink().getValue()))
                        .toList())
                .selfPromotions(resume.getSelfPromotions().stream()
                        .map(sp -> new SelfPromotion(
                                sp.getId(),
                                sp.getTitle(),
                                sp.getContent()))
                        .toList())
                .build();
    }

    /**
     * 職歴
     */
    @RequiredArgsConstructor
    @Getter
    public static class Career {
        private final UUID id;
        private final String companyName;
        private final YearMonth startDate;
        private final YearMonth endDate;
        private final boolean active;
    }

    /**
     * プロジェクト
     */
    @RequiredArgsConstructor
    @Getter
    public static class Project {
        private final UUID id;
        private final String companyName;
        private final YearMonth startDate;
        private final YearMonth endDate;
        private final boolean active;
        private final String name;
        private final String overview;
        private final String teamComp;
        private final String role;
        private final String achievement;
        private final Process process;
        private final TechStackDto techStack;
    }

    /**
     * 作業工程
     */
    @RequiredArgsConstructor
    @Getter
    public static class Process {
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
    @RequiredArgsConstructor
    @Getter
    public static class TechStackDto {
        private final FrontendDto frontend;
        private final BackendDto backend;
        private final InfrastructureDto infrastructure;
        private final ToolsDto tools;
    }

    /**
     * フロントエンドDTO
     */
    @RequiredArgsConstructor
    @Getter
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
    @RequiredArgsConstructor
    @Getter
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
    @RequiredArgsConstructor
    @Getter
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
    @RequiredArgsConstructor
    @Getter
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
     * 資格
     */
    @RequiredArgsConstructor
    @Getter
    public static class Certification {
        private final UUID id;
        private final String name;
        private final YearMonth date;
    }

    /**
     * ポートフォリオ
     */
    @RequiredArgsConstructor
    @Getter
    public static class Portfolio {
        private final UUID id;
        private final String name;
        private final String overview;
        private final String techStack;
        private final String link;
    }

    /**
     * ソーシャルリンク
     */
    @RequiredArgsConstructor
    @Getter
    public static class SocialLink {
        private final UUID id;
        private final String name;
        private final String link;
    }

    /**
     * 自己PR
     */
    @RequiredArgsConstructor
    @Getter
    public static class SelfPromotion {
        private final UUID id;
        private final String title;
        private final String content;
    }
}
