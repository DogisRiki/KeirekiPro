package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.model.resume.TechStack;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateProjectRequest;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.UpdateProjectUseCase;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UpdateProjectUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private UpdateProjectUseCase useCase;

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
    @DisplayName("プロジェクトを更新できる")
    void test1() {
        // リクエスト準備
        UpdateProjectRequest request = new UpdateProjectRequest();
        request.setCompanyName("会社A");
        request.setStartDate(YearMonth.of(2018, 1));
        request.setEndDate(YearMonth.of(2018, 12));
        request.setIsActive(Boolean.FALSE);
        request.setName("更新後プロジェクト");
        request.setOverview("更新後概要");
        request.setTeamComp("更新後チーム構成");
        request.setRole("更新後役割");
        request.setAchievement("更新後成果");
        // 工程
        request.setRequirements(Boolean.TRUE);
        request.setBasicDesign(Boolean.TRUE);
        request.setDetailedDesign(Boolean.FALSE);
        request.setImplementation(Boolean.TRUE);
        request.setIntegrationTest(Boolean.FALSE);
        request.setSystemTest(Boolean.TRUE);
        request.setMaintenance(Boolean.FALSE);
        // TechStack
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

        // 既存の職務経歴書とプロジェクトを準備（宣言位置を使用直前へ寄せる）
        Resume resume = buildResumeWithProjects(USER_ID);

        // 更新対象IDは、並び順に依存しないよう名前で特定する（宣言はexecute直前）
        UUID projectId = resume.getProjects().stream()
                .filter(p -> "プロジェクト1".equals(p.getName()))
                .map(Project::getId)
                .findFirst()
                .orElseThrow();

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        ResumeInfoUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID, projectId, request);

        // repository.find に渡された引数を検証
        ArgumentCaptor<UUID> findCaptor = ArgumentCaptor.forClass(UUID.class);
        verify(repository).find(findCaptor.capture());
        assertThat(findCaptor.getValue()).isEqualTo(RESUME_ID);

        // save() に渡された Resume をキャプチャ
        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        // 件数は変わらない（更新のみ）
        assertThat(saved.getProjects()).hasSize(2);

        // 更新対象が更新されていることを検証
        Project updated = saved.getProjects().stream()
                .filter(p -> p.getId().equals(projectId))
                .findFirst()
                .orElseThrow();

        assertThat(updated.getCompanyName().getValue()).isEqualTo("会社A");
        assertThat(updated.getPeriod().getStartDate()).isEqualTo(YearMonth.of(2018, 1));
        assertThat(updated.getPeriod().getEndDate()).isEqualTo(YearMonth.of(2018, 12));
        assertThat(updated.getPeriod().isActive()).isFalse();

        assertThat(updated.getName()).isEqualTo("更新後プロジェクト");
        assertThat(updated.getOverview()).isEqualTo("更新後概要");
        assertThat(updated.getTeamComp()).isEqualTo("更新後チーム構成");
        assertThat(updated.getRole()).isEqualTo("更新後役割");
        assertThat(updated.getAchievement()).isEqualTo("更新後成果");

        assertThat(updated.getProcess().isRequirements()).isTrue();
        assertThat(updated.getProcess().isBasicDesign()).isTrue();
        assertThat(updated.getProcess().isDetailedDesign()).isFalse();
        assertThat(updated.getProcess().isImplementation()).isTrue();
        assertThat(updated.getProcess().isIntegrationTest()).isFalse();
        assertThat(updated.getProcess().isSystemTest()).isTrue();
        assertThat(updated.getProcess().isMaintenance()).isFalse();

        assertThat(updated.getTechStack().getFrontend().getLanguages()).isEqualTo(List.of("TypeScript"));
        assertThat(updated.getTechStack().getBackend().getFrameworks()).isEqualTo(List.of("Spring Boot"));
        assertThat(updated.getTechStack().getInfrastructure().getDatabases()).isEqualTo(List.of("PostgreSQL"));
        assertThat(updated.getTechStack().getTools().getEditors()).isEqualTo(List.of("VSCode"));

        // 他のプロジェクトが保持されていることを検証（プロジェクト2）
        assertThat(saved.getProjects().stream()
                .anyMatch(p -> "プロジェクト2".equals(p.getName()))).isTrue();

        // save() されたエンティティからDTOを組み立てて比較
        ResumeInfoUseCaseDto expected = ResumeInfoUseCaseDto.convertToUseCaseDto(saved);
        assertThat(actual)
                .usingRecursiveComparison()
                .isEqualTo(expected);
    }

    @Test
    @DisplayName("対象の職務経歴書が存在しない場合、UseCaseExceptionがスローされる")
    void test2() {
        // リクエスト準備
        UpdateProjectRequest request = new UpdateProjectRequest();
        request.setCompanyName("会社A");
        request.setStartDate(YearMonth.of(2018, 1));
        request.setEndDate(YearMonth.of(2018, 12));
        request.setIsActive(Boolean.FALSE);
        request.setName("更新後プロジェクト");
        request.setOverview("更新後概要");
        request.setTeamComp("更新後チーム構成");
        request.setRole("更新後役割");
        request.setAchievement("更新後成果");
        request.setRequirements(Boolean.TRUE);
        request.setBasicDesign(Boolean.TRUE);
        request.setDetailedDesign(Boolean.FALSE);
        request.setImplementation(Boolean.TRUE);
        request.setIntegrationTest(Boolean.FALSE);
        request.setSystemTest(Boolean.TRUE);
        request.setMaintenance(Boolean.FALSE);

        // モック準備（対象の職務経歴書が存在しない）
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        // 実行＆検証
        UUID projectId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, projectId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書のプロジェクトを更新しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // リクエスト準備
        UpdateProjectRequest request = new UpdateProjectRequest();
        request.setCompanyName("会社A");
        request.setStartDate(YearMonth.of(2018, 1));
        request.setEndDate(YearMonth.of(2018, 12));
        request.setIsActive(Boolean.FALSE);
        request.setName("更新後プロジェクト");
        request.setOverview("更新後概要");
        request.setTeamComp("更新後チーム構成");
        request.setRole("更新後役割");
        request.setAchievement("更新後成果");
        request.setRequirements(Boolean.TRUE);
        request.setBasicDesign(Boolean.TRUE);
        request.setDetailedDesign(Boolean.FALSE);
        request.setImplementation(Boolean.TRUE);
        request.setIntegrationTest(Boolean.FALSE);
        request.setSystemTest(Boolean.TRUE);
        request.setMaintenance(Boolean.FALSE);

        // 職務経歴書（所有者は別ユーザー）を準備（宣言位置を使用直前へ寄せる）
        Resume resume = buildResumeWithProjects(OTHER_USER_ID);

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        UUID projectId = resume.getProjects().stream()
                .map(Project::getId)
                .findFirst()
                .orElseThrow();

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, projectId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("更新対象のプロジェクトが存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // リクエスト準備
        UpdateProjectRequest request = new UpdateProjectRequest();
        request.setCompanyName("会社A");
        request.setStartDate(YearMonth.of(2018, 1));
        request.setEndDate(YearMonth.of(2018, 12));
        request.setIsActive(Boolean.FALSE);
        request.setName("存在しないプロジェクト更新");
        request.setOverview("ダミー概要");
        request.setTeamComp("ダミーチーム構成");
        request.setRole("ダミー役割");
        request.setAchievement("ダミー成果");
        request.setRequirements(Boolean.TRUE);
        request.setBasicDesign(Boolean.FALSE);
        request.setDetailedDesign(Boolean.FALSE);
        request.setImplementation(Boolean.TRUE);
        request.setIntegrationTest(Boolean.FALSE);
        request.setSystemTest(Boolean.FALSE);
        request.setMaintenance(Boolean.FALSE);

        // 既存の職務経歴書を準備（宣言位置を使用直前へ寄せる）
        Resume resume = buildResumeWithProjects(USER_ID);

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        UUID missingProjectId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, missingProjectId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("対象のプロジェクトが存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    /**
     * 職歴2件・プロジェクト2件を持つ職務経歴書を作成するヘルパーメソッド
     */
    private Resume buildResumeWithProjects(UUID ownerId) {
        ErrorCollector errorCollector = new ErrorCollector();

        // 職務経歴書本体を再構築
        ResumeName resumeName = ResumeName.create(errorCollector, RESUME_NAME);
        FullName fullName = FullName.create(errorCollector, LAST_NAME, FIRST_NAME);

        // 職歴（プロジェクトで使用する会社名に対応させる）
        CompanyName companyA = CompanyName.create(errorCollector, "会社A");
        Period careerPeriodA = Period.create(errorCollector, YearMonth.of(2017, 1), YearMonth.of(2019, 12), false);
        var careerA = com.example.keirekipro.domain.model.resume.Career.create(errorCollector, companyA, careerPeriodA);

        CompanyName companyB = CompanyName.create(errorCollector, "会社B");
        Period careerPeriodB = Period.create(errorCollector, YearMonth.of(2019, 1), YearMonth.of(2021, 12), false);
        var careerB = com.example.keirekipro.domain.model.resume.Career.create(errorCollector, companyB, careerPeriodB);

        List<com.example.keirekipro.domain.model.resume.Career> careers = List.of(careerA, careerB);

        // 一旦、プロジェクトは空で再構築
        Resume base = Resume.reconstruct(
                RESUME_ID,
                ownerId,
                resumeName,
                DATE,
                fullName,
                CREATED_AT,
                UPDATED_AT,
                careers,
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of());

        // プロジェクト1（会社A）
        Project project1 = createProject(
                errorCollector,
                companyA,
                YearMonth.of(2018, 1),
                YearMonth.of(2018, 12),
                false,
                "プロジェクト1",
                "概要1",
                "チーム1",
                "役割1",
                "成果1");

        // プロジェクト2（会社B）
        Project project2 = createProject(
                errorCollector,
                companyB,
                YearMonth.of(2020, 1),
                YearMonth.of(2020, 12),
                false,
                "プロジェクト2",
                "概要2",
                "チーム2",
                "役割2",
                "成果2");

        Resume resumeWithProject1 = base.addProject(errorCollector, project1);
        return resumeWithProject1.addProject(errorCollector, project2);
    }

    /**
     * テスト用プロジェクト生成ヘルパー
     */
    private Project createProject(
            ErrorCollector errorCollector,
            CompanyName companyName,
            YearMonth start,
            YearMonth end,
            boolean isActive,
            String name,
            String overview,
            String teamComp,
            String role,
            String achievement) {

        Period period = Period.create(errorCollector, start, end, isActive);

        Project.Process process = Project.Process.create(
                true, // requirements
                true, // basicDesign
                true, // detailedDesign
                true, // implementation
                false, // integrationTest
                false, // systemTest
                false // maintenance
        );

        TechStack.Frontend frontend = TechStack.Frontend.create(
                List.of("TypeScript"),
                List.of("React"),
                List.of("MUI"),
                List.of("Vite"),
                List.of("npm"),
                List.of("ESLint"),
                List.of("Prettier"),
                List.of("RTL"));

        TechStack.Backend backend = TechStack.Backend.create(
                List.of("Java"),
                List.of("Spring Boot"),
                List.of("MyBatis"),
                List.of("Gradle"),
                List.of("npm"),
                List.of(),
                List.of(),
                List.of("JUnit"),
                List.of("MyBatis"),
                List.of("JWT"));

        TechStack.Infrastructure infrastructure = TechStack.Infrastructure.create(
                List.of("AWS"),
                List.of("Linux"),
                List.of("Docker"),
                List.of("PostgreSQL"),
                List.of("nginx"),
                List.of("Jenkins"),
                List.of("Terraform"),
                List.of("CloudWatch"),
                List.of("CloudWatch Logs"));

        TechStack.Tools tools = TechStack.Tools.create(
                List.of("Git"),
                List.of("Redmine"),
                List.of("Teams"),
                List.of("Confluence"),
                List.of("Postman"),
                List.of("Figma"),
                List.of("VSCode"),
                List.of("Windows"));

        TechStack techStack = TechStack.create(frontend, backend, infrastructure, tools);

        return Project.create(
                errorCollector,
                companyName,
                period,
                name,
                overview,
                teamComp,
                role,
                achievement,
                process,
                techStack);
    }
}
