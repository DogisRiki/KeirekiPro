package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.TechStack;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.CreateProjectRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * プロジェクト新規作成ユースケース
 */
@Service
@RequiredArgsConstructor
public class CreateProjectUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * プロジェクト新規作成ユースケースを実行する
     *
     * @param userId   ユーザーID
     * @param resumeId 職務経歴書ID
     * @param request  リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, CreateProjectRequest request) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        Notification notification = new Notification();

        CompanyName companyName = CompanyName.create(notification, request.getCompanyName());
        Period period = Period.create(notification, request.getStartDate(), request.getEndDate(),
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

        Project project = Project.create(
                notification,
                companyName,
                period,
                request.getName(),
                request.getOverview(),
                request.getTeamComp(),
                request.getRole(),
                request.getAchievement(),
                process,
                techStack);

        Resume updated = resume.addProject(notification, project);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
