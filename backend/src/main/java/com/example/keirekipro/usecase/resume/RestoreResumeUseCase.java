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
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.command.RestoreResumeCommand;
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
     * @param command コマンド
     * @return リストアされた職務経歴書情報
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(RestoreResumeCommand command) {
        UUID userId = command.getUserId();

        // バージョンチェック
        if (!ResumeBackupVersion.SUPPORTED_VERSION.equals(command.getVersion())) {
            throw new UseCaseException("サポートされていないバックアップバージョンです。");
        }

        // 上限チェック
        resumeLimitChecker.checkResumeCreateAllowed(userId);

        ErrorCollector errorCollector = new ErrorCollector();
        RestoreResumeCommand.ResumeCommand resumeCommand = command.getResume();

        // 職務経歴書名の構築
        ResumeName resumeName = ResumeName.create(errorCollector, resumeCommand.getResumeName());

        // 重複チェック（このDomainExceptionはそのまま伝播させる）
        resumeNameDuplicationCheckService.execute(userId, resumeName);

        // ドメインモデル再構築（ここで発生するDomainExceptionは破損/改ざんとみなす）
        Resume resume = buildResumeFromCommand(errorCollector, userId, resumeCommand, resumeName);

        // 保存
        resumeRepository.save(resume);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(resume);
    }

    /**
     * リクエストからドメインモデルを構築する
     * <p>
     * バックアップファイルから復元する際、ドメインバリデーションに失敗した場合は
     * ファイルが破損または改ざんされているとみなしUseCaseExceptionをスローする
     * </p>
     *
     * @param errorCollector エラー収集オブジェクト
     * @param userId ユーザーID
     * @param resumeCommand 復元対象の職務経歴書コマンド
     * @param resumeName 職務経歴書名
     * @return 職務経歴書エンティティ
     * @throws UseCaseException ファイルが破損または改ざんされている場合
     */
    private Resume buildResumeFromCommand(ErrorCollector errorCollector, UUID userId,
            RestoreResumeCommand.ResumeCommand resumeCommand, ResumeName resumeName) {
        try {
            // 氏名
            FullName fullName = FullName.create(errorCollector, resumeCommand.getLastName(),
                    resumeCommand.getFirstName());

            // 職歴
            List<Career> careers = buildCareers(errorCollector, resumeCommand.getCareers());

            // プロジェクト
            List<Project> projects = buildProjects(errorCollector, resumeCommand.getProjects());

            // 資格
            List<Certification> certifications = buildCertifications(errorCollector, resumeCommand.getCertifications());

            // ポートフォリオ
            List<Portfolio> portfolios = buildPortfolios(errorCollector, resumeCommand.getPortfolios());

            // SNSプラットフォーム
            List<SnsPlatform> snsPlatforms = buildSnsPlatforms(errorCollector, resumeCommand.getSnsPlatforms());

            // 自己PR
            List<SelfPromotion> selfPromotions = buildSelfPromotions(errorCollector, resumeCommand.getSelfPromotions());

            // 職務経歴書エンティティ新規構築
            return Resume.create(
                    errorCollector,
                    userId,
                    resumeName,
                    resumeCommand.getDate(),
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
            List<RestoreResumeCommand.CareerCommand> careerCommands) {
        if (careerCommands == null) {
            return List.of();
        }
        return careerCommands.stream()
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
            List<RestoreResumeCommand.ProjectCommand> projectCommands) {
        if (projectCommands == null) {
            return List.of();
        }
        return projectCommands.stream()
                .map(p -> {
                    RestoreResumeCommand.ProcessCommand processDto = p.getProcess();
                    RestoreResumeCommand.TechStackCommand techStackDto = p.getTechStack();

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
    private TechStack buildTechStack(RestoreResumeCommand.TechStackCommand techStackDto) {
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

        RestoreResumeCommand.FrontendCommand frontendDto = techStackDto.getFrontend();
        RestoreResumeCommand.BackendCommand backendDto = techStackDto.getBackend();
        RestoreResumeCommand.InfrastructureCommand infraDto = techStackDto.getInfrastructure();
        RestoreResumeCommand.ToolsCommand toolsDto = techStackDto.getTools();

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
            List<RestoreResumeCommand.CertificationCommand> certificationCommands) {
        if (certificationCommands == null) {
            return List.of();
        }
        return certificationCommands.stream()
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
            List<RestoreResumeCommand.PortfolioCommand> portfolioCommands) {
        if (portfolioCommands == null) {
            return List.of();
        }
        return portfolioCommands.stream()
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
            List<RestoreResumeCommand.SnsPlatformCommand> snsPlatformCommands) {
        if (snsPlatformCommands == null) {
            return List.of();
        }
        return snsPlatformCommands.stream()
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
            List<RestoreResumeCommand.SelfPromotionCommand> selfPromotionCommands) {
        if (selfPromotionCommands == null) {
            return List.of();
        }
        return selfPromotionCommands.stream()
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
