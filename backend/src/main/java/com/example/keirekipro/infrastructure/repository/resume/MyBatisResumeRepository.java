package com.example.keirekipro.infrastructure.repository.resume;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.CompanyName;
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
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.shared.Notification;

import org.springframework.stereotype.Repository;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書リポジトリ実装
 */
@Repository
@RequiredArgsConstructor
public class MyBatisResumeRepository implements ResumeRepository {

    private final ResumeMapper resumeMapper;

    @Override
    public List<Resume> findAll(UUID userId) {
        // 親テーブルからDTOを取得
        List<ResumeDto> dtoList = resumeMapper.selectAllByUserId(userId);

        // 各DTOに対して子テーブルを個別に読み込む
        dtoList.forEach(dto -> {
            UUID resumeId = dto.getId();
            dto.setCareers(resumeMapper.selectCareersByResumeId(resumeId));
            dto.setProjects(resumeMapper.selectProjectsByResumeId(resumeId));
            dto.setCertifications(resumeMapper.selectCertificationsByResumeId(resumeId));
            dto.setPortfolios(resumeMapper.selectPortfoliosByResumeId(resumeId));
            dto.setSocialLinks(resumeMapper.selectSocialLinksByResumeId(resumeId));
            dto.setSelfPromotions(resumeMapper.selectSelfPromotionsByResumeId(resumeId));
        });

        // DTO → エンティティ変換
        return dtoList.stream()
                .map(this::toEntity)
                .toList();
    }

    @Override
    public Optional<Resume> find(UUID resumeId) {
        // 親テーブルからDTOを取得
        Optional<ResumeDto> optDto = resumeMapper.selectByResumeId(resumeId);
        if (optDto.isEmpty()) {
            return Optional.empty();
        }
        ResumeDto dto = optDto.get();

        // 子テーブルを個別に読み込んでDTOにセット
        dto.setCareers(resumeMapper.selectCareersByResumeId(resumeId));
        dto.setProjects(resumeMapper.selectProjectsByResumeId(resumeId));
        dto.setCertifications(resumeMapper.selectCertificationsByResumeId(resumeId));
        dto.setPortfolios(resumeMapper.selectPortfoliosByResumeId(resumeId));
        dto.setSocialLinks(resumeMapper.selectSocialLinksByResumeId(resumeId));
        dto.setSelfPromotions(resumeMapper.selectSelfPromotionsByResumeId(resumeId));

        // DTO → エンティティ変換
        return Optional.of(toEntity(dto));
    }

    @Override
    public void save(Resume resume) {
        // エンティティ → DTO に変換
        ResumeDto dto = toDto(resume);
        UUID resumeId = dto.getId();

        // 親テーブル(resumes)をupsert
        resumeMapper.upsert(dto);

        // 職歴
        resumeMapper.deleteCareersByResumeId(resumeId);
        for (ResumeDto.CareerDto careerDto : dto.getCareers()) {
            resumeMapper.insertCareer(careerDto);
        }

        // プロジェクト
        resumeMapper.deleteProjectsByResumeId(resumeId);
        for (ResumeDto.ProjectDto projectDto : dto.getProjects()) {
            resumeMapper.insertProject(projectDto);
        }

        // 資格
        resumeMapper.deleteCertificationsByResumeId(resumeId);
        for (ResumeDto.CertificationDto certDto : dto.getCertifications()) {
            resumeMapper.insertCertification(certDto);
        }

        // ポートフォリオ
        resumeMapper.deletePortfoliosByResumeId(resumeId);
        for (ResumeDto.PortfolioDto portfolioDto : dto.getPortfolios()) {
            resumeMapper.insertPortfolio(portfolioDto);
        }

        // ソーシャルリンク
        resumeMapper.deleteSocialLinksByResumeId(resumeId);
        for (ResumeDto.SocialLinkDto socialLinkDto : dto.getSocialLinks()) {
            resumeMapper.insertSocialLink(socialLinkDto);
        }

        // 自己PR
        resumeMapper.deleteSelfPromotionsByResumeId(resumeId);
        for (ResumeDto.SelfPromotionDto selfDto : dto.getSelfPromotions()) {
            resumeMapper.insertSelfPromotion(selfDto);
        }
    }

    @Override
    public void delete(UUID resumeId) {
        // 子テーブルをすべて削除してから、親テーブルを削除
        resumeMapper.deleteCareersByResumeId(resumeId);
        resumeMapper.deleteProjectsByResumeId(resumeId);
        resumeMapper.deleteCertificationsByResumeId(resumeId);
        resumeMapper.deletePortfoliosByResumeId(resumeId);
        resumeMapper.deleteSocialLinksByResumeId(resumeId);
        resumeMapper.deleteSelfPromotionsByResumeId(resumeId);

        // 親テーブル (resumes) を削除
        resumeMapper.delete(resumeId);
    }

    /**
     * DTO → エンティティへの変換
     */
    private Resume toEntity(ResumeDto dto) {

        Notification notification = new Notification();

        // 職歴
        List<Career> careers = dto.getCareers().stream()
                .map(d -> Career.reconstruct(
                        d.getId(),
                        CompanyName.create(notification, d.getCompanyName()),
                        Period.create(notification, d.getStartDate(), d.getEndDate(), d.getIsActive())))
                .toList();

        // プロジェクト
        List<Project> projects = dto.getProjects().stream()
                .map(d -> Project.reconstruct(
                        d.getId(),
                        CompanyName.create(notification, d.getCompanyName()),
                        Period.create(notification, d.getStartDate(), d.getEndDate(), d.getIsActive()),
                        d.getName(),
                        d.getOverview(),
                        d.getTeamComp(),
                        d.getRole(),
                        d.getAchievement(),
                        Project.Process.create(
                                d.getRequirements(),
                                d.getBasicDesign(),
                                d.getDetailedDesign(),
                                d.getImplementation(),
                                d.getIntegrationTest(),
                                d.getSystemTest(),
                                d.getMaintenance()),
                        TechStack.create(
                                TechStack.Frontend.create(
                                        d.getFrontendLanguages(),
                                        d.getFrontendFramework(),
                                        d.getFrontendLibraries(),
                                        d.getFrontendBuildTool(),
                                        d.getFrontendPackageManager(),
                                        d.getFrontendLinters(),
                                        d.getFrontendFormatters(),
                                        d.getFrontendTestingTools()),
                                TechStack.Backend.create(
                                        d.getBackendLanguages(),
                                        d.getBackendFramework(),
                                        d.getBackendLibraries(),
                                        d.getBackendBuildTool(),
                                        d.getBackendPackageManager(),
                                        d.getBackendLinters(),
                                        d.getBackendFormatters(),
                                        d.getBackendTestingTools(),
                                        d.getOrmTools(),
                                        d.getAuth()),
                                TechStack.Infrastructure.create(
                                        d.getClouds(),
                                        d.getOperatingSystem(),
                                        d.getContainers(),
                                        d.getDatabase(),
                                        d.getWebServer(),
                                        d.getCiCdTool(),
                                        d.getIacTools(),
                                        d.getMonitoringTools(),
                                        d.getLoggingTools()),
                                TechStack.Tools.create(
                                        d.getSourceControl(),
                                        d.getProjectManagement(),
                                        d.getCommunicationTool(),
                                        d.getDocumentationTools(),
                                        d.getApiDevelopmentTools(),
                                        d.getDesignTools(),
                                        d.getEditor(),
                                        d.getDevelopmentEnvironment()))))
                .toList();

        // 資格
        List<Certification> certifications = dto.getCertifications().stream()
                .map(d -> Certification.reconstruct(
                        d.getId(),
                        d.getName(),
                        d.getDate()))
                .toList();

        // ポートフォリオ
        List<Portfolio> portfolios = dto.getPortfolios().stream()
                .map(d -> Portfolio.reconstruct(
                        d.getId(),
                        d.getName(),
                        d.getOverview(),
                        d.getTechStack(),
                        Link.create(notification, d.getLink())))
                .toList();

        // ソーシャルリンク
        List<SocialLink> socialLinks = dto.getSocialLinks().stream()
                .map(d -> SocialLink.reconstruct(
                        d.getId(),
                        d.getName(),
                        Link.create(notification, d.getLink())))
                .toList();

        // 自己PR
        List<SelfPromotion> selfPromotions = dto.getSelfPromotions().stream()
                .map(d -> SelfPromotion.reconstruct(
                        d.getId(),
                        d.getTitle(),
                        d.getContent()))
                .toList();

        // Resumeを再構築
        return Resume.reconstruct(
                dto.getId(),
                dto.getUserId(),
                ResumeName.create(notification, dto.getName()),
                dto.getDate(),
                FullName.create(notification, dto.getLastName(), dto.getFirstName()),
                dto.getCreatedAt(),
                dto.getUpdatedAt(),
                careers,
                projects,
                certifications,
                portfolios,
                socialLinks,
                selfPromotions);
    }

    /**
     * エンティティ → DTO への変換
     */
    private ResumeDto toDto(Resume resume) {
        ResumeDto dto = new ResumeDto();
        dto.setId(resume.getId());
        dto.setUserId(resume.getUserId());
        dto.setName(resume.getName().getValue());
        dto.setDate(resume.getDate());
        dto.setLastName(resume.getFullName().getLastName());
        dto.setFirstName(resume.getFullName().getFirstName());
        dto.setCreatedAt(resume.getCreatedAt());
        dto.setUpdatedAt(resume.getUpdatedAt());

        UUID resumeId = resume.getId();

        // 職歴リスト
        List<ResumeDto.CareerDto> careerDtos = resume.getCareers().stream()
                .map(c -> {
                    ResumeDto.CareerDto d = new ResumeDto.CareerDto();
                    d.setId(c.getId());
                    d.setResumeId(resumeId);
                    d.setCompanyName(c.getCompanyName().getValue());
                    d.setStartDate(c.getPeriod().getStartDate());
                    d.setEndDate(c.getPeriod().getEndDate());
                    d.setIsActive(c.getPeriod().isActive());
                    return d;
                })
                .toList();
        dto.setCareers(careerDtos);

        // プロジェクトリスト
        List<ResumeDto.ProjectDto> projectDtos = resume.getProjects().stream()
                .map(p -> {
                    ResumeDto.ProjectDto d = new ResumeDto.ProjectDto();
                    d.setId(p.getId());
                    d.setResumeId(resumeId);
                    d.setCompanyName(p.getCompanyName().getValue());
                    d.setStartDate(p.getPeriod().getStartDate());
                    d.setEndDate(p.getPeriod().getEndDate());
                    d.setIsActive(p.getPeriod().isActive());
                    d.setName(p.getName());
                    d.setOverview(p.getOverview());
                    d.setTeamComp(p.getTeamComp());
                    d.setRole(p.getRole());
                    d.setAchievement(p.getAchievement());

                    // Process の各フラグをセット
                    d.setRequirements(p.getProcess().isRequirements());
                    d.setBasicDesign(p.getProcess().isBasicDesign());
                    d.setDetailedDesign(p.getProcess().isDetailedDesign());
                    d.setImplementation(p.getProcess().isImplementation());
                    d.setIntegrationTest(p.getProcess().isIntegrationTest());
                    d.setSystemTest(p.getProcess().isSystemTest());
                    d.setMaintenance(p.getProcess().isMaintenance());

                    // TechStack
                    TechStack techStack = p.getTechStack();
                    TechStack.Frontend frontend = techStack.getFrontend();
                    TechStack.Backend backend = techStack.getBackend();
                    TechStack.Infrastructure infra = techStack.getInfrastructure();
                    TechStack.Tools tools = techStack.getTools();

                    // フロントエンド
                    d.setFrontendLanguages(frontend.getLanguages());
                    d.setFrontendFramework(frontend.getFramework());
                    d.setFrontendLibraries(frontend.getLibraries());
                    d.setFrontendBuildTool(frontend.getBuildTool());
                    d.setFrontendPackageManager(frontend.getPackageManager());
                    d.setFrontendLinters(frontend.getLinters());
                    d.setFrontendFormatters(frontend.getFormatters());
                    d.setFrontendTestingTools(frontend.getTestingTools());

                    // バックエンド
                    d.setBackendLanguages(backend.getLanguages());
                    d.setBackendFramework(backend.getFramework());
                    d.setBackendLibraries(backend.getLibraries());
                    d.setBackendBuildTool(backend.getBuildTool());
                    d.setBackendPackageManager(backend.getPackageManager());
                    d.setBackendLinters(backend.getLinters());
                    d.setBackendFormatters(backend.getFormatters());
                    d.setBackendTestingTools(backend.getTestingTools());
                    d.setOrmTools(backend.getOrmTools());
                    d.setAuth(backend.getAuth());

                    // インフラ
                    d.setClouds(infra.getClouds());
                    d.setOperatingSystem(infra.getOperatingSystem());
                    d.setContainers(infra.getContainers());
                    d.setDatabase(infra.getDatabase());
                    d.setWebServer(infra.getWebServer());
                    d.setCiCdTool(infra.getCiCdTool());
                    d.setIacTools(infra.getIacTools());
                    d.setMonitoringTools(infra.getMonitoringTools());
                    d.setLoggingTools(infra.getLoggingTools());

                    // 開発支援ツール
                    d.setSourceControl(tools.getSourceControl());
                    d.setProjectManagement(tools.getProjectManagement());
                    d.setCommunicationTool(tools.getCommunicationTool());
                    d.setDocumentationTools(tools.getDocumentationTools());
                    d.setApiDevelopmentTools(tools.getApiDevelopmentTools());
                    d.setDesignTools(tools.getDesignTools());
                    d.setEditor(tools.getEditor());
                    d.setDevelopmentEnvironment(tools.getDevelopmentEnvironment());

                    return d;
                })
                .toList();
        dto.setProjects(projectDtos);

        // 資格リスト
        List<ResumeDto.CertificationDto> certificationDtos = resume.getCertifications().stream()
                .map(c -> {
                    ResumeDto.CertificationDto d = new ResumeDto.CertificationDto();
                    d.setId(c.getId());
                    d.setResumeId(resumeId);
                    d.setName(c.getName());
                    d.setDate(c.getDate());
                    return d;
                })
                .toList();
        dto.setCertifications(certificationDtos);

        // ポートフォリオリスト
        List<ResumeDto.PortfolioDto> portfolioDtos = resume.getPortfolios().stream()
                .map(pf -> {
                    ResumeDto.PortfolioDto d = new ResumeDto.PortfolioDto();
                    d.setId(pf.getId());
                    d.setResumeId(resumeId);
                    d.setName(pf.getName());
                    d.setOverview(pf.getOverview());
                    d.setTechStack(pf.getTechStack());
                    d.setLink(pf.getLink().getValue());
                    return d;
                })
                .toList();
        dto.setPortfolios(portfolioDtos);

        // ソーシャルリンクリスト
        List<ResumeDto.SocialLinkDto> socialLinkDtos = resume.getSocialLinks().stream()
                .map(sl -> {
                    ResumeDto.SocialLinkDto d = new ResumeDto.SocialLinkDto();
                    d.setId(sl.getId());
                    d.setResumeId(resumeId);
                    d.setName(sl.getName());
                    d.setLink(sl.getLink().getValue());
                    return d;
                })
                .toList();
        dto.setSocialLinks(socialLinkDtos);

        // 自己PRリスト
        List<ResumeDto.SelfPromotionDto> selfDtos = resume.getSelfPromotions().stream()
                .map(sp -> {
                    ResumeDto.SelfPromotionDto d = new ResumeDto.SelfPromotionDto();
                    d.setId(sp.getId());
                    d.setResumeId(resumeId);
                    d.setTitle(sp.getTitle());
                    d.setContent(sp.getContent());
                    return d;
                })
                .toList();
        dto.setSelfPromotions(selfDtos);

        return dto;
    }
}
