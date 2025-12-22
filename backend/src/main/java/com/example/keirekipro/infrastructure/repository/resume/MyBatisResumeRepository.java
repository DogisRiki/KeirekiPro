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
import com.example.keirekipro.domain.model.resume.SnsPlatform;
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
            dto.setSnsPlatforms(resumeMapper.selectSnsPlatformsByResumeId(resumeId));
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
        dto.setSnsPlatforms(resumeMapper.selectSnsPlatformsByResumeId(resumeId));
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

        // SNSプラットフォーム
        resumeMapper.deleteSnsPlatformsByResumeId(resumeId);
        for (ResumeDto.SnsPlatformDto snsPlatformDto : dto.getSnsPlatforms()) {
            resumeMapper.insertSnsPlatform(snsPlatformDto);
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
        resumeMapper.deleteSnsPlatformsByResumeId(resumeId);
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
                                        d.getFrontendFrameworks(),
                                        d.getFrontendLibraries(),
                                        d.getFrontendBuildTools(),
                                        d.getFrontendPackageManagers(),
                                        d.getFrontendLinters(),
                                        d.getFrontendFormatters(),
                                        d.getFrontendTestingTools()),
                                TechStack.Backend.create(
                                        d.getBackendLanguages(),
                                        d.getBackendFrameworks(),
                                        d.getBackendLibraries(),
                                        d.getBackendBuildTools(),
                                        d.getBackendPackageManagers(),
                                        d.getBackendLinters(),
                                        d.getBackendFormatters(),
                                        d.getBackendTestingTools(),
                                        d.getOrmTools(),
                                        d.getAuth()),
                                TechStack.Infrastructure.create(
                                        d.getClouds(),
                                        d.getOperatingSystems(),
                                        d.getContainers(),
                                        d.getDatabases(),
                                        d.getWebServers(),
                                        d.getCiCdTools(),
                                        d.getIacTools(),
                                        d.getMonitoringTools(),
                                        d.getLoggingTools()),
                                TechStack.Tools.create(
                                        d.getSourceControls(),
                                        d.getProjectManagements(),
                                        d.getCommunicationTools(),
                                        d.getDocumentationTools(),
                                        d.getApiDevelopmentTools(),
                                        d.getDesignTools(),
                                        d.getEditors(),
                                        d.getDevelopmentEnvironments()))))
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

        // SNSプラットフォーム
        List<SnsPlatform> snsPlatforms = dto.getSnsPlatforms().stream()
                .map(d -> SnsPlatform.reconstruct(
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
                snsPlatforms,
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
        dto.setLastName(
                resume.getFullName() != null ? resume.getFullName().getLastName() : null);
        dto.setFirstName(
                resume.getFullName() != null ? resume.getFullName().getFirstName() : null);
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
                    d.setFrontendFrameworks(frontend.getFrameworks());
                    d.setFrontendLibraries(frontend.getLibraries());
                    d.setFrontendBuildTools(frontend.getBuildTools());
                    d.setFrontendPackageManagers(frontend.getPackageManagers());
                    d.setFrontendLinters(frontend.getLinters());
                    d.setFrontendFormatters(frontend.getFormatters());
                    d.setFrontendTestingTools(frontend.getTestingTools());

                    // バックエンド
                    d.setBackendLanguages(backend.getLanguages());
                    d.setBackendFrameworks(backend.getFrameworks());
                    d.setBackendLibraries(backend.getLibraries());
                    d.setBackendBuildTools(backend.getBuildTools());
                    d.setBackendPackageManagers(backend.getPackageManagers());
                    d.setBackendLinters(backend.getLinters());
                    d.setBackendFormatters(backend.getFormatters());
                    d.setBackendTestingTools(backend.getTestingTools());
                    d.setOrmTools(backend.getOrmTools());
                    d.setAuth(backend.getAuth());

                    // インフラ
                    d.setClouds(infra.getClouds());
                    d.setOperatingSystems(infra.getOperatingSystems());
                    d.setContainers(infra.getContainers());
                    d.setDatabases(infra.getDatabases());
                    d.setWebServers(infra.getWebServers());
                    d.setCiCdTools(infra.getCiCdTools());
                    d.setIacTools(infra.getIacTools());
                    d.setMonitoringTools(infra.getMonitoringTools());
                    d.setLoggingTools(infra.getLoggingTools());

                    // 開発支援ツール
                    d.setSourceControls(tools.getSourceControls());
                    d.setProjectManagements(tools.getProjectManagements());
                    d.setCommunicationTools(tools.getCommunicationTools());
                    d.setDocumentationTools(tools.getDocumentationTools());
                    d.setApiDevelopmentTools(tools.getApiDevelopmentTools());
                    d.setDesignTools(tools.getDesignTools());
                    d.setEditors(tools.getEditors());
                    d.setDevelopmentEnvironments(tools.getDevelopmentEnvironments());

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

        // SNSプラットフォームリスト
        List<ResumeDto.SnsPlatformDto> snsPlatFormDtos = resume.getSnsPlatforms().stream()
                .map(sp -> {
                    ResumeDto.SnsPlatformDto d = new ResumeDto.SnsPlatformDto();
                    d.setId(sp.getId());
                    d.setResumeId(resumeId);
                    d.setName(sp.getName());
                    d.setLink(sp.getLink().getValue());
                    return d;
                })
                .toList();
        dto.setSnsPlatforms(snsPlatFormDtos);

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
