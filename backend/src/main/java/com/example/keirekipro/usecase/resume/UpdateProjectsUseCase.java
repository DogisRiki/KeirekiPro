package com.example.keirekipro.usecase.resume;

import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.TechStack;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateProjectsRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書 プロジェクト更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateProjectsUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * プロジェクト更新ユースケースを実行する
     *
     * @param userId   ユーザーID
     * @param resumeId 職務経歴書ID
     * @param request  リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UpdateProjectsRequest request) {

        // 職務経歴書の存在チェック
        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        // 認可チェック（本人の職務経歴書か）
        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        Notification notification = new Notification();

        // 更新中の職務経歴書
        Resume updatedResume = resume;

        // 既存のプロジェクトをIDで引けるようにマッピング
        Map<UUID, Project> remainingProjectsById = resume.getProjects().stream()
                .collect(Collectors.toMap(Project::getId, Function.identity()));

        // リクエストの内容に従って追加・更新
        for (UpdateProjectsRequest.ProjectRequest projectRequest : request.getProjects()) {

            // 会社名・期間
            CompanyName companyName = CompanyName.create(notification, projectRequest.getCompanyName());
            Period period = Period.create(
                    notification,
                    projectRequest.getStartDate(),
                    projectRequest.getEndDate(),
                    Boolean.TRUE.equals(projectRequest.getIsActive()));

            // 担当工程
            Project.Process process = Project.Process.create(
                    Boolean.TRUE.equals(projectRequest.getRequirements()),
                    Boolean.TRUE.equals(projectRequest.getBasicDesign()),
                    Boolean.TRUE.equals(projectRequest.getDetailedDesign()),
                    Boolean.TRUE.equals(projectRequest.getImplementation()),
                    Boolean.TRUE.equals(projectRequest.getIntegrationTest()),
                    Boolean.TRUE.equals(projectRequest.getSystemTest()),
                    Boolean.TRUE.equals(projectRequest.getMaintenance()));

            // 技術スタック
            TechStack.Frontend frontend = TechStack.Frontend.create(
                    projectRequest.getFrontendLanguages(),
                    projectRequest.getFrontendFramework(),
                    projectRequest.getFrontendLibraries(),
                    projectRequest.getFrontendBuildTool(),
                    projectRequest.getFrontendPackageManager(),
                    projectRequest.getFrontendLinters(),
                    projectRequest.getFrontendFormatters(),
                    projectRequest.getFrontendTestingTools());

            TechStack.Backend backend = TechStack.Backend.create(
                    projectRequest.getBackendLanguages(),
                    projectRequest.getBackendFramework(),
                    projectRequest.getBackendLibraries(),
                    projectRequest.getBackendBuildTool(),
                    projectRequest.getBackendPackageManager(),
                    projectRequest.getBackendLinters(),
                    projectRequest.getBackendFormatters(),
                    projectRequest.getBackendTestingTools(),
                    projectRequest.getOrmTools(),
                    projectRequest.getAuth());

            TechStack.Infrastructure infrastructure = TechStack.Infrastructure.create(
                    projectRequest.getClouds(),
                    projectRequest.getOperatingSystem(),
                    projectRequest.getContainers(),
                    projectRequest.getDatabase(),
                    projectRequest.getWebServer(),
                    projectRequest.getCiCdTool(),
                    projectRequest.getIacTools(),
                    projectRequest.getMonitoringTools(),
                    projectRequest.getLoggingTools());

            TechStack.Tools tools = TechStack.Tools.create(
                    projectRequest.getSourceControl(),
                    projectRequest.getProjectManagement(),
                    projectRequest.getCommunicationTool(),
                    projectRequest.getDocumentationTools(),
                    projectRequest.getApiDevelopmentTools(),
                    projectRequest.getDesignTools(),
                    projectRequest.getEditor(),
                    projectRequest.getDevelopmentEnvironment());

            TechStack techStack = TechStack.create(frontend, backend, infrastructure, tools);

            // 新規追加
            if (projectRequest.getId() == null) {
                Project newProject = Project.create(
                        notification,
                        companyName,
                        period,
                        projectRequest.getName(),
                        projectRequest.getOverview(),
                        projectRequest.getTeamComp(),
                        projectRequest.getRole(),
                        projectRequest.getAchievement(),
                        process,
                        techStack);

                updatedResume = updatedResume.addProject(notification, newProject);
                continue;
            }

            // 既存更新
            Project currentProject = remainingProjectsById.remove(projectRequest.getId());
            if (currentProject == null) {
                throw new UseCaseException("更新対象の職務内容情報が存在しません。");
            }

            Project updatedProject = currentProject
                    .changeCompanyName(notification, companyName)
                    .changePeriod(notification, period)
                    .changeName(notification, projectRequest.getName())
                    .changeOverview(notification, projectRequest.getOverview())
                    .changeTeamComp(notification, projectRequest.getTeamComp())
                    .changeRole(notification, projectRequest.getRole())
                    .changeAchievement(notification, projectRequest.getAchievement())
                    .changeProcess(process)
                    .changeTechStack(techStack);

            updatedResume = updatedResume.updateProject(notification, updatedProject);
        }

        // リクエストに含まれなかったプロジェクトは削除
        for (Project projectToDelete : remainingProjectsById.values()) {
            updatedResume = updatedResume.removeProject(projectToDelete.getId());
        }

        resumeRepository.save(updatedResume);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updatedResume);
    }
}
