package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.TechStack;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.command.UpdateProjectCommand;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.ResourceNotFoundUseCaseException;

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
     * @param command コマンド
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UpdateProjectCommand command) {
        UUID userId = command.getUserId();
        String resumeId = command.getResumeId();
        UUID projectId = command.getProjectId();
        UUID resolvedResumeId = ResumeIdResolver.resolve(resumeId);

        Resume resume = resumeRepository.find(resolvedResumeId)
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。");
        }

        Project existing = resume.getProjects().stream()
                .filter(p -> p.getId().equals(projectId))
                .findFirst()
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象のプロジェクトが存在しません。"));

        ErrorCollector errorCollector = new ErrorCollector();

        CompanyName companyName = CompanyName.create(errorCollector, command.getCompanyName());
        Period period = Period.create(errorCollector, command.getStartDate(), command.getEndDate(),
                command.getActive());

        Project.Process process = Project.Process.create(
                command.getRequirements(),
                command.getBasicDesign(),
                command.getDetailedDesign(),
                command.getImplementation(),
                command.getIntegrationTest(),
                command.getSystemTest(),
                command.getMaintenance());

        TechStack techStack = TechStack.create(
                TechStack.Frontend.create(
                        command.getFrontendLanguages(),
                        command.getFrontendFrameworks(),
                        command.getFrontendLibraries(),
                        command.getFrontendBuildTools(),
                        command.getFrontendPackageManagers(),
                        command.getFrontendLinters(),
                        command.getFrontendFormatters(),
                        command.getFrontendTestingTools()),
                TechStack.Backend.create(
                        command.getBackendLanguages(),
                        command.getBackendFrameworks(),
                        command.getBackendLibraries(),
                        command.getBackendBuildTools(),
                        command.getBackendPackageManagers(),
                        command.getBackendLinters(),
                        command.getBackendFormatters(),
                        command.getBackendTestingTools(),
                        command.getOrmTools(),
                        command.getAuth()),
                TechStack.Infrastructure.create(
                        command.getClouds(),
                        command.getOperatingSystems(),
                        command.getContainers(),
                        command.getDatabases(),
                        command.getWebServers(),
                        command.getCiCdTools(),
                        command.getIacTools(),
                        command.getMonitoringTools(),
                        command.getLoggingTools()),
                TechStack.Tools.create(
                        command.getSourceControls(),
                        command.getProjectManagements(),
                        command.getCommunicationTools(),
                        command.getDocumentationTools(),
                        command.getApiDevelopmentTools(),
                        command.getDesignTools(),
                        command.getEditors(),
                        command.getDevelopmentEnvironments()));

        Project updatedProject = existing
                .changeCompanyName(errorCollector, companyName)
                .changePeriod(errorCollector, period)
                .changeName(errorCollector, command.getName())
                .changeOverview(errorCollector, command.getOverview())
                .changeTeamComp(errorCollector, command.getTeamComp())
                .changeRole(errorCollector, command.getRole())
                .changeAchievement(errorCollector, command.getAchievement())
                .changeProcess(process)
                .changeTechStack(techStack);

        Resume updated = resume.updateProject(errorCollector, updatedProject);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
