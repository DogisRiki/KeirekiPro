package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.TechStack;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateProjectRequest;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * プロジェクト更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateProjectUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * プロジェクト更新ユースケースを実行する
     *
     * @param userId    ユーザーID
     * @param resumeId  職務経歴書ID
     * @param projectId プロジェクトID
     * @param request   リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UUID projectId, UpdateProjectRequest request) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        Project existing = resume.getProjects().stream()
                .filter(p -> p.getId().equals(projectId))
                .findFirst()
                .orElseThrow(() -> new UseCaseException("対象のプロジェクトが存在しません。"));

        ErrorCollector errorCollector = new ErrorCollector();

        CompanyName companyName = CompanyName.create(errorCollector, request.getCompanyName());
        Period period = Period.create(errorCollector, request.getStartDate(), request.getEndDate(),
                request.getIsActive());

        Project.Process process = Project.Process.create(
                request.getRequirements(),
                request.getBasicDesign(),
                request.getDetailedDesign(),
                request.getImplementation(),
                request.getIntegrationTest(),
                request.getSystemTest(),
                request.getMaintenance());

        TechStack techStack = TechStack.create(
                TechStack.Frontend.create(
                        request.getFrontendLanguages(),
                        request.getFrontendFrameworks(),
                        request.getFrontendLibraries(),
                        request.getFrontendBuildTools(),
                        request.getFrontendPackageManagers(),
                        request.getFrontendLinters(),
                        request.getFrontendFormatters(),
                        request.getFrontendTestingTools()),
                TechStack.Backend.create(
                        request.getBackendLanguages(),
                        request.getBackendFrameworks(),
                        request.getBackendLibraries(),
                        request.getBackendBuildTools(),
                        request.getBackendPackageManagers(),
                        request.getBackendLinters(),
                        request.getBackendFormatters(),
                        request.getBackendTestingTools(),
                        request.getOrmTools(),
                        request.getAuth()),
                TechStack.Infrastructure.create(
                        request.getClouds(),
                        request.getOperatingSystems(),
                        request.getContainers(),
                        request.getDatabases(),
                        request.getWebServers(),
                        request.getCiCdTools(),
                        request.getIacTools(),
                        request.getMonitoringTools(),
                        request.getLoggingTools()),
                TechStack.Tools.create(
                        request.getSourceControls(),
                        request.getProjectManagements(),
                        request.getCommunicationTools(),
                        request.getDocumentationTools(),
                        request.getApiDevelopmentTools(),
                        request.getDesignTools(),
                        request.getEditors(),
                        request.getDevelopmentEnvironments()));

        Project updatedProject = existing
                .changeCompanyName(errorCollector, companyName)
                .changePeriod(errorCollector, period)
                .changeName(errorCollector, request.getName())
                .changeOverview(errorCollector, request.getOverview())
                .changeTeamComp(errorCollector, request.getTeamComp())
                .changeRole(errorCollector, request.getRole())
                .changeAchievement(errorCollector, request.getAchievement())
                .changeProcess(process)
                .changeTechStack(techStack);

        Resume updated = resume.updateProject(errorCollector, updatedProject);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
