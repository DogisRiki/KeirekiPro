package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.CreateProjectRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.CreateProjectUseCase;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.resume.policy.ResumeLimitChecker;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class CreateProjectUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @Mock
    private ResumeLimitChecker checker;

    @InjectMocks
    private CreateProjectUseCase useCase;

    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID OTHER_USER_ID = UUID.fromString("33333333-3333-3333-3333-333333333333");

    private static final String RESUME_NAME = "職務経歴書1";
    private static final LocalDate DATE = LocalDate.of(2021, 5, 20);
    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2021, 5, 15, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2021, 5, 18, 15, 30);

    @Test
    @DisplayName("プロジェクトを新規作成できる")
    void test1() {
        CreateProjectRequest request = buildRequest();

        doNothing().when(checker).checkProjectAddAllowed(RESUME_ID);
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(buildResumeWithCareer(USER_ID)));

        ResumeInfoUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID, request);

        // 上限チェックの検証
        verify(checker).checkProjectAddAllowed(RESUME_ID);

        verify(repository).find(RESUME_ID);

        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        assertThat(saved.getProjects()).hasSize(1);
        Project created = saved.getProjects().get(0);

        assertThat(created.getCompanyName().getValue()).isEqualTo("会社A");
        assertThat(created.getPeriod().getStartDate()).isEqualTo(YearMonth.of(2018, 1));
        assertThat(created.getPeriod().getEndDate()).isEqualTo(YearMonth.of(2018, 12));
        assertThat(created.getPeriod().isActive()).isFalse();
        assertThat(created.getName()).isEqualTo("プロジェクト1");
        assertThat(created.getOverview()).isEqualTo("概要1");
        assertThat(created.getTeamComp()).isEqualTo("チーム1");
        assertThat(created.getRole()).isEqualTo("役割1");
        assertThat(created.getAchievement()).isEqualTo("成果1");

        assertThat(created.getProcess().isRequirements()).isTrue();
        assertThat(created.getProcess().isBasicDesign()).isTrue();
        assertThat(created.getProcess().isDetailedDesign()).isFalse();
        assertThat(created.getProcess().isImplementation()).isTrue();
        assertThat(created.getProcess().isIntegrationTest()).isFalse();
        assertThat(created.getProcess().isSystemTest()).isTrue();
        assertThat(created.getProcess().isMaintenance()).isFalse();

        assertThat(created.getTechStack().getFrontend().getLanguages()).isEqualTo(List.of("TypeScript"));
        assertThat(created.getTechStack().getBackend().getFrameworks()).isEqualTo(List.of("Spring Boot"));
        assertThat(created.getTechStack().getInfrastructure().getDatabases()).isEqualTo(List.of("PostgreSQL"));
        assertThat(created.getTechStack().getTools().getEditors()).isEqualTo(List.of("VSCode"));

        ResumeInfoUseCaseDto expected = ResumeInfoUseCaseDto.convertToUseCaseDto(saved);
        assertThat(actual).usingRecursiveComparison().isEqualTo(expected);
    }

    @Test
    @DisplayName("対象の職務経歴書が存在しない場合、UseCaseExceptionがスローされる")
    void test2() {
        CreateProjectRequest request = buildRequest();

        doNothing().when(checker).checkProjectAddAllowed(RESUME_ID);
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(checker).checkProjectAddAllowed(RESUME_ID);
        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書にプロジェクトを作成しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        CreateProjectRequest request = buildRequest();

        doNothing().when(checker).checkProjectAddAllowed(RESUME_ID);
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(buildResumeWithCareer(OTHER_USER_ID)));

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(checker).checkProjectAddAllowed(RESUME_ID);
        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("プロジェクトが上限件数である場合、例外がスローされ後続処理が行われない")
    void test4() {
        CreateProjectRequest request = buildRequest();

        doThrow(new UseCaseException("上限")).when(checker).checkProjectAddAllowed(RESUME_ID);

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("上限");

        verify(checker).checkProjectAddAllowed(RESUME_ID);
        verify(repository, never()).find(any());
        verify(repository, never()).save(any());
    }

    private CreateProjectRequest buildRequest() {
        CreateProjectRequest request = new CreateProjectRequest();
        request.setCompanyName("会社A");
        request.setStartDate(YearMonth.of(2018, 1));
        request.setEndDate(YearMonth.of(2018, 12));
        request.setIsActive(Boolean.FALSE);

        request.setName("プロジェクト1");
        request.setOverview("概要1");
        request.setTeamComp("チーム1");
        request.setRole("役割1");
        request.setAchievement("成果1");

        request.setRequirements(Boolean.TRUE);
        request.setBasicDesign(Boolean.TRUE);
        request.setDetailedDesign(Boolean.FALSE);
        request.setImplementation(Boolean.TRUE);
        request.setIntegrationTest(Boolean.FALSE);
        request.setSystemTest(Boolean.TRUE);
        request.setMaintenance(Boolean.FALSE);

        request.setFrontendLanguages(List.of("TypeScript"));
        request.setFrontendFrameworks(List.of("React"));
        request.setFrontendLibraries(List.of("MUI"));
        request.setFrontendBuildTools(List.of("Vite"));
        request.setFrontendPackageManagers(List.of("npm"));
        request.setFrontendLinters(List.of("ESLint"));
        request.setFrontendFormatters(List.of("Prettier"));
        request.setFrontendTestingTools(List.of("RTL"));

        request.setBackendLanguages(List.of("Java"));
        request.setBackendFrameworks(List.of("Spring Boot"));
        request.setBackendLibraries(List.of("MyBatis"));
        request.setBackendBuildTools(List.of("Gradle"));
        request.setBackendPackageManagers(List.of("npm"));
        request.setBackendLinters(List.of());
        request.setBackendFormatters(List.of());
        request.setBackendTestingTools(List.of("JUnit"));
        request.setOrmTools(List.of("MyBatis"));
        request.setAuth(List.of("JWT"));

        request.setClouds(List.of("AWS"));
        request.setOperatingSystems(List.of("Linux"));
        request.setContainers(List.of("Docker"));
        request.setDatabases(List.of("PostgreSQL"));
        request.setWebServers(List.of("nginx"));
        request.setCiCdTools(List.of("Jenkins"));
        request.setIacTools(List.of("Terraform"));
        request.setMonitoringTools(List.of("CloudWatch"));
        request.setLoggingTools(List.of("CloudWatch Logs"));

        request.setSourceControls(List.of("Git"));
        request.setProjectManagements(List.of("Redmine"));
        request.setCommunicationTools(List.of("Teams"));
        request.setDocumentationTools(List.of("Confluence"));
        request.setApiDevelopmentTools(List.of("Postman"));
        request.setDesignTools(List.of("Figma"));
        request.setEditors(List.of("VSCode"));
        request.setDevelopmentEnvironments(List.of("Windows"));

        return request;
    }

    private Resume buildResumeWithCareer(UUID ownerId) {
        Notification notification = new Notification();

        ResumeName resumeName = ResumeName.create(notification, RESUME_NAME);
        FullName fullName = FullName.create(notification, LAST_NAME, FIRST_NAME);

        CompanyName companyName = CompanyName.create(notification, "会社A");
        Period period = Period.create(notification, YearMonth.of(2017, 1), YearMonth.of(2019, 12), false);
        Career career = Career.create(notification, companyName, period);

        return Resume.reconstruct(
                RESUME_ID,
                ownerId,
                resumeName,
                DATE,
                fullName,
                CREATED_AT,
                UPDATED_AT,
                List.of(career), // careers
                List.of(), // projects
                List.of(), // certifications
                List.of(), // portfolios
                List.of(), // socialLinks
                List.of() // selfPromotions
        );
    }
}
