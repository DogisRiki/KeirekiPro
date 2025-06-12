package com.example.keirekipro.helper;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.model.resume.SocialLink;
import com.example.keirekipro.domain.model.resume.TechStack;
import com.example.keirekipro.domain.model.resume.TechStack.Dependencies;
import com.example.keirekipro.domain.model.resume.TechStack.Infrastructure;
import com.example.keirekipro.domain.model.resume.TechStack.Tools;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;

/**
 * Resume関連のオブジェクトを生成するヘルパークラス
 */
public class ResumeObjectBuilder {

    /**
     * Resumeエンティティを生成するヘルパーメソッド
     *
     * @param resumeId  職務経歴書ID
     * @param userId    ユーザーID
     * @param name      職務経歴書名
     * @param date      日付
     * @param lastName  姓
     * @param firstName 名
     * @param createdAt 作成日時
     * @param updatedAt 更新日時
     * @return Resumeエンティティ
     */
    public static Resume buildResume(UUID resumeId,
            UUID userId,
            String name,
            LocalDate date,
            String lastName,
            String firstName,
            LocalDateTime createdAt,
            LocalDateTime updatedAt) {
        Notification notif = new Notification();
        ResumeName rn = ResumeName.create(notif, name);
        FullName fn = FullName.create(notif, lastName, firstName);

        Period period = Period.create(new Notification(), YearMonth.of(2020, 1), YearMonth.of(2020, 12), false);
        Career career = Career.create("CompanyA", period);
        Project.Process process = Project.Process.create(true, false, false, true, false, false, false);

        Dependencies deps = Dependencies.create(List.of("Spring"), List.of("JUnit"), List.of("Mockito"), List.of("JPA"),
                List.of("Maven"));
        Infrastructure infra = Infrastructure.create(List.of("AWS"), List.of("Docker"), List.of("Postgres"),
                List.of("NGINX"), List.of("Jenkins"), List.of("Terraform"), List.of("Prometheus"), List.of("ELK"));
        Tools tools = Tools.create(List.of("Git"), List.of("JIRA"), List.of("Slack"), List.of("Confluence"),
                List.of("Postman"), List.of("Figma"));
        TechStack tech = TechStack.create(List.of("Java", "Kotlin"), deps, infra, tools);

        Project project = Project.create("CompanyA", period, "ProjName", "Overview", "TeamComp", "Role", "Achievement",
                process, tech);
        Certification cert = Certification.create("Oracle Certified", YearMonth.of(2019, 6));
        Portfolio port = Portfolio.create("Portfolio1", "Desc", "TechStackDesc",
                Link.create(new Notification(), "https://example.com"));
        SocialLink social = SocialLink.create("GitHub", Link.create(new Notification(), "https://github.com"));
        SelfPromotion self = SelfPromotion.create("Title1", "Content1");

        return Resume.reconstruct(
                resumeId,
                userId,
                rn,
                date,
                fn,
                createdAt,
                updatedAt,
                List.of(career),
                List.of(project),
                List.of(cert),
                List.of(port),
                List.of(social),
                List.of(self));
    }

    /**
     * ResumeInfoUseCaseDtoを生成するヘルパーメソッド
     *
     * @param resumeId  職務経歴書ID
     * @param userId    ユーザーID
     * @param name      職務経歴書名
     * @param date      日付
     * @param lastName  姓
     * @param firstName 名
     * @param createdAt 作成日時
     * @param updatedAt 更新日時
     * @return ResumeInfoUseCaseDto
     */
    public static ResumeInfoUseCaseDto buildResumeInfoUseCaseDto(UUID resumeId,
            UUID userId,
            String name,
            LocalDate date,
            String lastName,
            String firstName,
            LocalDateTime createdAt,
            LocalDateTime updatedAt) {
        Resume resume = buildResume(resumeId, userId, name, date, lastName, firstName, createdAt, updatedAt);
        return ResumeInfoUseCaseDto.convertToUseCaseDto(resume);
    }

    /**
     * ResumeDtoを生成するヘルパーメソッド
     *
     * @param resumeId  職務経歴書ID
     * @param userId    ユーザーID
     * @param name      職務経歴書名
     * @param date      日付
     * @param lastName  姓
     * @param firstName 名
     * @param createdAt 作成日時
     * @param updatedAt 更新日時
     * @return ResumeDto
     */
    public static ResumeDto buildResumeDto(
            UUID resumeId,
            UUID userId,
            String name,
            LocalDate date,
            String lastName,
            String firstName,
            LocalDateTime createdAt,
            LocalDateTime updatedAt) {

        // ドメインを生成
        Resume r = buildResume(resumeId, userId, name, date, lastName, firstName, createdAt, updatedAt);

        // DTO にマッピング
        ResumeDto dto = new ResumeDto();
        dto.setId(r.getId());
        dto.setUserId(r.getUserId());
        dto.setName(r.getName().getValue());
        dto.setDate(r.getDate());
        dto.setLastName(r.getFullName().getLastName());
        dto.setFirstName(r.getFullName().getFirstName());
        dto.setCreatedAt(createdAt);
        dto.setUpdatedAt(updatedAt);

        // 職歴
        dto.setCareers(r.getCareers().stream().map(c -> {
            ResumeDto.CareerDto cd = new ResumeDto.CareerDto();
            cd.setId(c.getId());
            cd.setResumeId(r.getId());
            cd.setCompanyName(c.getCompanyName());
            cd.setStartDate(c.getPeriod().getStartDate());
            cd.setEndDate(c.getPeriod().getEndDate());
            cd.setIsActive(c.getPeriod().isActive());
            return cd;
        }).collect(Collectors.toList()));

        // プロジェクト
        dto.setProjects(r.getProjects().stream().map(p -> {
            ResumeDto.ProjectDto pd = new ResumeDto.ProjectDto();
            pd.setId(p.getId());
            pd.setResumeId(r.getId());
            pd.setCompanyName(p.getCompanyName());
            pd.setStartDate(p.getPeriod().getStartDate());
            pd.setEndDate(p.getPeriod().getEndDate());
            pd.setIsActive(p.getPeriod().isActive());
            pd.setName(p.getName());
            pd.setOverview(p.getOverview());
            pd.setTeamComp(p.getTeamComp());
            pd.setRole(p.getRole());
            pd.setAchievement(p.getAchievement());
            // Process
            pd.setRequirements(p.getProcess().isRequirements());
            pd.setBasicDesign(p.getProcess().isBasicDesign());
            pd.setDetailedDesign(p.getProcess().isDetailedDesign());
            pd.setImplementation(p.getProcess().isImplementation());
            pd.setIntegrationTest(p.getProcess().isIntegrationTest());
            pd.setSystemTest(p.getProcess().isSystemTest());
            pd.setMaintenance(p.getProcess().isMaintenance());
            // TechStack
            TechStack ts = p.getTechStack();
            pd.setLanguages(ts.getLanguages());
            // Dependencies
            Dependencies dep = ts.getDependencies();
            pd.setFrameworks(dep.getFrameworks());
            pd.setLibraries(dep.getLibraries());
            pd.setTestingTools(dep.getTestingTools());
            pd.setOrmTools(dep.getOrmTools());
            pd.setPackageManagers(dep.getPackageManagers());
            // Infrastructure
            Infrastructure inf = ts.getInfrastructure();
            pd.setClouds(inf.getClouds());
            pd.setContainers(inf.getContainers());
            pd.setDatabases(inf.getDatabases());
            pd.setWebServers(inf.getWebServers());
            pd.setCiCdTools(inf.getCiCdTools());
            pd.setIacTools(inf.getIacTools());
            pd.setMonitoringTools(inf.getMonitoringTools());
            pd.setLoggingTools(inf.getLoggingTools());
            // Tools
            Tools tls = ts.getTools();
            pd.setSourceControls(tls.getSourceControls());
            pd.setProjectManagements(tls.getProjectManagements());
            pd.setCommunicationTools(tls.getCommunicationTools());
            pd.setDocumentationTools(tls.getDocumentationTools());
            pd.setApiDevelopmentTools(tls.getApiDevelopmentTools());
            pd.setDesignTools(tls.getDesignTools());
            return pd;
        }).collect(Collectors.toList()));

        // 資格
        dto.setCertifications(r.getCertifications().stream().map(c -> {
            ResumeDto.CertificationDto cd = new ResumeDto.CertificationDto();
            cd.setId(c.getId());
            cd.setResumeId(r.getId());
            cd.setName(c.getName());
            cd.setDate(c.getDate());
            return cd;
        }).collect(Collectors.toList()));

        // ポートフォリオ
        dto.setPortfolios(r.getPortfolios().stream().map(pf -> {
            ResumeDto.PortfolioDto pod = new ResumeDto.PortfolioDto();
            pod.setId(pf.getId());
            pod.setResumeId(r.getId());
            pod.setName(pf.getName());
            pod.setOverview(pf.getOverview());
            pod.setTechStack(pf.getTechStack());
            pod.setLink(pf.getLink().getValue());
            return pod;
        }).collect(Collectors.toList()));

        // ソーシャルリンク
        dto.setSocialLinks(r.getSocialLinks().stream().map(sl -> {
            ResumeDto.SocialLinkDto sd = new ResumeDto.SocialLinkDto();
            sd.setId(sl.getId());
            sd.setResumeId(r.getId());
            sd.setName(sl.getName());
            sd.setLink(sl.getLink().getValue());
            return sd;
        }).collect(Collectors.toList()));

        // 自己PR
        dto.setSelfPromotions(r.getSelfPromotions().stream().map(sp -> {
            ResumeDto.SelfPromotionDto sd = new ResumeDto.SelfPromotionDto();
            sd.setId(sp.getId());
            sd.setResumeId(r.getId());
            sd.setTitle(sp.getTitle());
            sd.setContent(sp.getContent());
            return sd;
        }).collect(Collectors.toList()));

        return dto;
    }
}
