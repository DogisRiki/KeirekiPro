package com.example.keirekipro.usecase.resume;

import java.util.List;
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
import com.example.keirekipro.domain.service.resume.ResumeNameDuplicationCheckService;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.presentation.resume.dto.RestoreResumeRequest;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.resume.policy.ResumeBackupVersion;
import com.example.keirekipro.usecase.resume.policy.ResumeLimitChecker;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書リストアユースケース
 */
@Service
@RequiredArgsConstructor
public class RestoreResumeUseCase {

    private final ResumeLimitChecker resumeLimitChecker;

    private final ResumeNameDuplicationCheckService resumeNameDuplicationCheckService;

    private final ResumeRepository resumeRepository;

    /**
     * 職務経歴書リストアユースケースを実行する
     *
     * @param userId  ユーザーID
     * @param request リストアリクエスト
     * @return リストアされた職務経歴書情報
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, RestoreResumeRequest request) {

        // バージョンチェック
        if (!ResumeBackupVersion.SUPPORTED_VERSION.equals(request.getVersion())) {
            throw new UseCaseException("サポートされていないバックアップバージョンです。");
        }

        // 上限チェック
        resumeLimitChecker.checkResumeCreateAllowed(userId);

        ErrorCollector errorCollector = new ErrorCollector();
        RestoreResumeRequest.ResumeDto resumeDto = request.getResume();

        // 職務経歴書名の構築
        ResumeName resumeName = ResumeName.create(errorCollector, resumeDto.getResumeName());

        // 重複チェック（このDomainExceptionはそのまま伝播させる）
        resumeNameDuplicationCheckService.execute(userId, resumeName);

        // ドメインモデル再構築（ここで発生するDomainExceptionは破損/改ざんとみなす）
        Resume resume = buildResumeFromRequest(errorCollector, userId, resumeDto, resumeName);

        // 保存
        resumeRepository.save(resume);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(resume);
    }

    /**
     * リクエストからドメインモデルを構築する
     * <p>
     * バックアップファイルから復元する際、ドメインバリデーションに失敗した場合は
     * ファイルが破損または改ざんされているとみなしUseCaseExceptionをスローする。
     * </p>
     *
     * @param errorCollector エラー収集オブジェクト
     * @param userId         ユーザーID
     * @param resumeDto      リクエストの職務経歴書DTO
     * @param resumeName     職務経歴書名
     * @return 職務経歴書エンティティ
     * @throws UseCaseException ファイルが破損または改ざんされている場合
     */
    private Resume buildResumeFromRequest(ErrorCollector errorCollector, UUID userId,
            RestoreResumeRequest.ResumeDto resumeDto, ResumeName resumeName) {
        try {
            // 氏名
            FullName fullName = FullName.create(errorCollector, resumeDto.getLastName(), resumeDto.getFirstName());

            // 職歴
            List<Career> careers = buildCareers(errorCollector, resumeDto.getCareers());

            // プロジェクト
            List<Project> projects = buildProjects(errorCollector, resumeDto.getProjects());

            // 資格
            List<Certification> certifications = buildCertifications(errorCollector, resumeDto.getCertifications());

            // ポートフォリオ
            List<Portfolio> portfolios = buildPortfolios(errorCollector, resumeDto.getPortfolios());

            // SNSプラットフォーム
            List<SnsPlatform> snsPlatforms = buildSnsPlatforms(errorCollector, resumeDto.getSnsPlatforms());

            // 自己PR
            List<SelfPromotion> selfPromotions = buildSelfPromotions(errorCollector, resumeDto.getSelfPromotions());

            // 職務経歴書エンティティ新規構築
            return Resume.create(
                    errorCollector,
                    userId,
                    resumeName,
                    resumeDto.getDate(),
                    fullName,
                    careers,
                    projects,
                    certifications,
                    portfolios,
                    snsPlatforms,
                    selfPromotions);

        } catch (DomainException e) {
            throw new UseCaseException("バックアップファイルが不正なためリストアできません。\n別のバックアップファイルでお試しください。");
        }
    }

    /**
     * 職歴リストを構築する
     */
    private List<Career> buildCareers(ErrorCollector errorCollector,
            List<RestoreResumeRequest.CareerDto> careerDtos) {
        if (careerDtos == null) {
            return List.of();
        }
        return careerDtos.stream()
                .map(c -> Career.create(
                        errorCollector,
                        CompanyName.create(errorCollector, c.getCompanyName()),
                        Period.create(errorCollector, c.getStartDate(), c.getEndDate(), c.isActive())))
                .toList();
    }

    /**
     * プロジェクトリストを構築する
     */
    private List<Project> buildProjects(ErrorCollector errorCollector,
            List<RestoreResumeRequest.ProjectDto> projectDtos) {
        if (projectDtos == null) {
            return List.of();
        }
        return projectDtos.stream()
                .map(p -> {
                    RestoreResumeRequest.ProcessDto processDto = p.getProcess();
                    RestoreResumeRequest.TechStackDto techStackDto = p.getTechStack();

                    Project.Process process = Project.Process.create(
                            processDto != null && processDto.isRequirements(),
                            processDto != null && processDto.isBasicDesign(),
                            processDto != null && processDto.isDetailedDesign(),
                            processDto != null && processDto.isImplementation(),
                            processDto != null && processDto.isIntegrationTest(),
                            processDto != null && processDto.isSystemTest(),
                            processDto != null && processDto.isMaintenance());

                    TechStack techStack = buildTechStack(techStackDto);

                    return Project.create(
                            errorCollector,
                            CompanyName.create(errorCollector, p.getCompanyName()),
                            Period.create(errorCollector, p.getStartDate(), p.getEndDate(), p.isActive()),
                            p.getName(),
                            p.getOverview(),
                            p.getTeamComp(),
                            p.getRole(),
                            p.getAchievement(),
                            process,
                            techStack);
                })
                .toList();
    }

    /**
     * 技術スタックを構築する
     */
    private TechStack buildTechStack(RestoreResumeRequest.TechStackDto techStackDto) {
        if (techStackDto == null) {
            return TechStack.create(
                    TechStack.Frontend.create(
                            List.of(), List.of(), List.of(), List.of(),
                            List.of(), List.of(), List.of(), List.of()),
                    TechStack.Backend.create(
                            List.of(), List.of(), List.of(), List.of(),
                            List.of(), List.of(), List.of(), List.of(),
                            List.of(), List.of()),
                    TechStack.Infrastructure.create(
                            List.of(), List.of(), List.of(), List.of(),
                            List.of(), List.of(), List.of(), List.of(), List.of()),
                    TechStack.Tools.create(
                            List.of(), List.of(), List.of(), List.of(),
                            List.of(), List.of(), List.of(), List.of()));
        }

        RestoreResumeRequest.FrontendDto frontendDto = techStackDto.getFrontend();
        RestoreResumeRequest.BackendDto backendDto = techStackDto.getBackend();
        RestoreResumeRequest.InfrastructureDto infraDto = techStackDto.getInfrastructure();
        RestoreResumeRequest.ToolsDto toolsDto = techStackDto.getTools();

        TechStack.Frontend frontend = TechStack.Frontend.create(
                nullSafeList(frontendDto != null ? frontendDto.getLanguages() : null),
                nullSafeList(frontendDto != null ? frontendDto.getFrameworks() : null),
                nullSafeList(frontendDto != null ? frontendDto.getLibraries() : null),
                nullSafeList(frontendDto != null ? frontendDto.getBuildTools() : null),
                nullSafeList(frontendDto != null ? frontendDto.getPackageManagers() : null),
                nullSafeList(frontendDto != null ? frontendDto.getLinters() : null),
                nullSafeList(frontendDto != null ? frontendDto.getFormatters() : null),
                nullSafeList(frontendDto != null ? frontendDto.getTestingTools() : null));

        TechStack.Backend backend = TechStack.Backend.create(
                nullSafeList(backendDto != null ? backendDto.getLanguages() : null),
                nullSafeList(backendDto != null ? backendDto.getFrameworks() : null),
                nullSafeList(backendDto != null ? backendDto.getLibraries() : null),
                nullSafeList(backendDto != null ? backendDto.getBuildTools() : null),
                nullSafeList(backendDto != null ? backendDto.getPackageManagers() : null),
                nullSafeList(backendDto != null ? backendDto.getLinters() : null),
                nullSafeList(backendDto != null ? backendDto.getFormatters() : null),
                nullSafeList(backendDto != null ? backendDto.getTestingTools() : null),
                nullSafeList(backendDto != null ? backendDto.getOrmTools() : null),
                nullSafeList(backendDto != null ? backendDto.getAuth() : null));

        TechStack.Infrastructure infrastructure = TechStack.Infrastructure.create(
                nullSafeList(infraDto != null ? infraDto.getClouds() : null),
                nullSafeList(infraDto != null ? infraDto.getOperatingSystems() : null),
                nullSafeList(infraDto != null ? infraDto.getContainers() : null),
                nullSafeList(infraDto != null ? infraDto.getDatabases() : null),
                nullSafeList(infraDto != null ? infraDto.getWebServers() : null),
                nullSafeList(infraDto != null ? infraDto.getCiCdTools() : null),
                nullSafeList(infraDto != null ? infraDto.getIacTools() : null),
                nullSafeList(infraDto != null ? infraDto.getMonitoringTools() : null),
                nullSafeList(infraDto != null ? infraDto.getLoggingTools() : null));

        TechStack.Tools tools = TechStack.Tools.create(
                nullSafeList(toolsDto != null ? toolsDto.getSourceControls() : null),
                nullSafeList(toolsDto != null ? toolsDto.getProjectManagements() : null),
                nullSafeList(toolsDto != null ? toolsDto.getCommunicationTools() : null),
                nullSafeList(toolsDto != null ? toolsDto.getDocumentationTools() : null),
                nullSafeList(toolsDto != null ? toolsDto.getApiDevelopmentTools() : null),
                nullSafeList(toolsDto != null ? toolsDto.getDesignTools() : null),
                nullSafeList(toolsDto != null ? toolsDto.getEditors() : null),
                nullSafeList(toolsDto != null ? toolsDto.getDevelopmentEnvironments() : null));

        return TechStack.create(frontend, backend, infrastructure, tools);
    }

    /**
     * 資格リストを構築する
     */
    private List<Certification> buildCertifications(ErrorCollector errorCollector,
            List<RestoreResumeRequest.CertificationDto> certificationDtos) {
        if (certificationDtos == null) {
            return List.of();
        }
        return certificationDtos.stream()
                .map(c -> Certification.create(
                        errorCollector,
                        c.getName(),
                        c.getDate()))
                .toList();
    }

    /**
     * ポートフォリオリストを構築する
     */
    private List<Portfolio> buildPortfolios(ErrorCollector errorCollector,
            List<RestoreResumeRequest.PortfolioDto> portfolioDtos) {
        if (portfolioDtos == null) {
            return List.of();
        }
        return portfolioDtos.stream()
                .map(pf -> Portfolio.create(
                        errorCollector,
                        pf.getName(),
                        pf.getOverview(),
                        pf.getTechStack(),
                        Link.create(errorCollector, pf.getLink())))
                .toList();
    }

    /**
     * SNSプラットフォームリストを構築する
     */
    private List<SnsPlatform> buildSnsPlatforms(ErrorCollector errorCollector,
            List<RestoreResumeRequest.SnsPlatformDto> snsPlatformDtos) {
        if (snsPlatformDtos == null) {
            return List.of();
        }
        return snsPlatformDtos.stream()
                .map(sp -> SnsPlatform.create(
                        errorCollector,
                        sp.getName(),
                        Link.create(errorCollector, sp.getLink())))
                .toList();
    }

    /**
     * 自己PRリストを構築する
     */
    private List<SelfPromotion> buildSelfPromotions(ErrorCollector errorCollector,
            List<RestoreResumeRequest.SelfPromotionDto> selfPromotionDtos) {
        if (selfPromotionDtos == null) {
            return List.of();
        }
        return selfPromotionDtos.stream()
                .map(sp -> SelfPromotion.create(
                        errorCollector,
                        sp.getTitle(),
                        sp.getContent()))
                .toList();
    }

    /**
     * nullの場合は空リストを返す
     */
    private <T> List<T> nullSafeList(List<T> list) {
        return list != null ? list : List.of();
    }
}
