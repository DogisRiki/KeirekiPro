package com.example.keirekipro.usecase.resume;

import java.time.Instant;
import java.util.UUID;

import com.example.keirekipro.shared.utils.FileUtil;
import com.example.keirekipro.usecase.query.resume.ResumeBackupQuery;
import com.example.keirekipro.usecase.query.resume.dto.ResumeBackupQueryDto;
import com.example.keirekipro.usecase.resume.dto.BackupResumeUseCaseDto;
import com.example.keirekipro.usecase.resume.policy.ResumeBackupVersion;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書バックアップユースケース
 */
@Service
@RequiredArgsConstructor
public class BackupResumeUseCase {

    private final ResumeBackupQuery resumeBackupQuery;

    /**
     * バックアップファイル拡張子
     */
    private static final String BACKUP_FILE_EXTENSION = "_backup.json";

    /**
     * 職務経歴書バックアップユースケースを実行する
     *
     * @param userId   ユーザーID
     * @param resumeId 職務経歴書ID
     * @return バックアップ用ユースケースDTO
     */
    public BackupResumeUseCaseDto execute(UUID userId, UUID resumeId) {

        // データ取得
        ResumeBackupQueryDto resumeData = resumeBackupQuery.findByIdForBackup(resumeId, userId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        // ファイル名作成
        String baseName = FileUtil.sanitizeFileName(resumeData.getResumeName(), "resume");
        String fileName = baseName + BACKUP_FILE_EXTENSION;

        // レスポンスを構築
        return BackupResumeUseCaseDto.builder()
                .fileName(fileName)
                .contentType(MediaType.APPLICATION_JSON_VALUE)
                .version(ResumeBackupVersion.SUPPORTED_VERSION)
                .exportedAt(Instant.now())
                .resume(convertToResumeDto(resumeData))
                .build();
    }

    /**
     * クエリDTOをユースケースDTO用のResumeDtoに変換する
     *
     * @param queryDto クエリDTO
     * @return ユースケースDTO用のResumeDto
     */
    private BackupResumeUseCaseDto.ResumeDto convertToResumeDto(ResumeBackupQueryDto queryDto) {
        return BackupResumeUseCaseDto.ResumeDto.builder()
                .resumeName(queryDto.getResumeName())
                .date(queryDto.getDate())
                .lastName(queryDto.getLastName())
                .firstName(queryDto.getFirstName())
                .careers(queryDto.getCareers().stream()
                        .map(c -> BackupResumeUseCaseDto.CareerDto.builder()
                                .companyName(c.getCompanyName())
                                .startDate(c.getStartDate())
                                .endDate(c.getEndDate())
                                .active(c.isActive())
                                .build())
                        .toList())
                .projects(queryDto.getProjects().stream()
                        .map(p -> BackupResumeUseCaseDto.ProjectDto.builder()
                                .companyName(p.getCompanyName())
                                .startDate(p.getStartDate())
                                .endDate(p.getEndDate())
                                .active(p.isActive())
                                .name(p.getName())
                                .overview(p.getOverview())
                                .teamComp(p.getTeamComp())
                                .role(p.getRole())
                                .achievement(p.getAchievement())
                                .process(BackupResumeUseCaseDto.ProcessDto.builder()
                                        .requirements(p.getProcess().isRequirements())
                                        .basicDesign(p.getProcess().isBasicDesign())
                                        .detailedDesign(p.getProcess().isDetailedDesign())
                                        .implementation(p.getProcess().isImplementation())
                                        .integrationTest(p.getProcess().isIntegrationTest())
                                        .systemTest(p.getProcess().isSystemTest())
                                        .maintenance(p.getProcess().isMaintenance())
                                        .build())
                                .techStack(BackupResumeUseCaseDto.TechStackDto.builder()
                                        .frontend(BackupResumeUseCaseDto.FrontendDto.builder()
                                                .languages(p.getTechStack().getFrontend().getLanguages())
                                                .frameworks(p.getTechStack().getFrontend().getFrameworks())
                                                .libraries(p.getTechStack().getFrontend().getLibraries())
                                                .buildTools(p.getTechStack().getFrontend().getBuildTools())
                                                .packageManagers(p.getTechStack().getFrontend().getPackageManagers())
                                                .linters(p.getTechStack().getFrontend().getLinters())
                                                .formatters(p.getTechStack().getFrontend().getFormatters())
                                                .testingTools(p.getTechStack().getFrontend().getTestingTools())
                                                .build())
                                        .backend(BackupResumeUseCaseDto.BackendDto.builder()
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
                                        .infrastructure(BackupResumeUseCaseDto.InfrastructureDto.builder()
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
                                        .tools(BackupResumeUseCaseDto.ToolsDto.builder()
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
                .certifications(queryDto.getCertifications().stream()
                        .map(c -> BackupResumeUseCaseDto.CertificationDto.builder()
                                .name(c.getName())
                                .date(c.getDate())
                                .build())
                        .toList())
                .portfolios(queryDto.getPortfolios().stream()
                        .map(pf -> BackupResumeUseCaseDto.PortfolioDto.builder()
                                .name(pf.getName())
                                .overview(pf.getOverview())
                                .techStack(pf.getTechStack())
                                .link(pf.getLink())
                                .build())
                        .toList())
                .snsPlatforms(queryDto.getSnsPlatforms().stream()
                        .map(sp -> BackupResumeUseCaseDto.SnsPlatformDto.builder()
                                .name(sp.getName())
                                .link(sp.getLink())
                                .build())
                        .toList())
                .selfPromotions(queryDto.getSelfPromotions().stream()
                        .map(sp -> BackupResumeUseCaseDto.SelfPromotionDto.builder()
                                .title(sp.getTitle())
                                .content(sp.getContent())
                                .build())
                        .toList())
                .build();
    }
}
