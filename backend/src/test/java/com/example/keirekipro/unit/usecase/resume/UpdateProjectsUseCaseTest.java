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
import com.example.keirekipro.presentation.resume.dto.UpdateProjectsRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.UpdateProjectsUseCase;
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
class UpdateProjectsUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private UpdateProjectsUseCase useCase;

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
    @DisplayName("プロジェクトを追加・更新・削除できる")
    void test1() {
        // 既存の職務経歴書とプロジェクトを準備
        Resume resume = buildResumeWithProjects(USER_ID);

        // getProjects() は並び替え済みのコピーを返すため、固定名に依存せず既存1件を特定する
        Project originalProject1 = resume.getProjects().stream()
                .findFirst()
                .orElseThrow();

        // リクエスト準備
        // 1件目: 既存プロジェクト1を更新
        UpdateProjectsRequest.ProjectRequest updateRequest = new UpdateProjectsRequest.ProjectRequest();
        updateRequest.setId(originalProject1.getId());
        updateRequest.setCompanyName("会社A");
        updateRequest.setStartDate(YearMonth.of(2018, 1));
        updateRequest.setEndDate(YearMonth.of(2018, 12));
        updateRequest.setIsActive(Boolean.FALSE);
        updateRequest.setName("更新後プロジェクト");
        updateRequest.setOverview("更新後概要");
        updateRequest.setTeamComp("更新後チーム構成");
        updateRequest.setRole("更新後役割");
        updateRequest.setAchievement("更新後成果");
        // 工程
        updateRequest.setRequirements(Boolean.TRUE);
        updateRequest.setBasicDesign(Boolean.TRUE);
        updateRequest.setDetailedDesign(Boolean.FALSE);
        updateRequest.setImplementation(Boolean.TRUE);
        updateRequest.setIntegrationTest(Boolean.FALSE);
        updateRequest.setSystemTest(Boolean.TRUE);
        updateRequest.setMaintenance(Boolean.FALSE);
        // TechStack
        updateRequest.setFrontendLanguages(List.of("TypeScript"));
        updateRequest.setFrontendFrameworks(List.of("React"));
        updateRequest.setFrontendLibraries(List.of("MUI"));
        updateRequest.setFrontendBuildTools(List.of("Vite"));
        updateRequest.setFrontendPackageManagers(List.of("npm"));
        updateRequest.setFrontendLinters(List.of("ESLint"));
        updateRequest.setFrontendFormatters(List.of("Prettier"));
        updateRequest.setFrontendTestingTools(List.of("RTL"));

        updateRequest.setBackendLanguages(List.of("Java"));
        updateRequest.setBackendFrameworks(List.of("Spring Boot"));
        updateRequest.setBackendLibraries(List.of("MyBatis"));
        updateRequest.setBackendBuildTools(List.of("Gradle"));
        updateRequest.setBackendPackageManagers(List.of("npm"));
        updateRequest.setBackendLinters(List.of());
        updateRequest.setBackendFormatters(List.of());
        updateRequest.setBackendTestingTools(List.of("JUnit"));
        updateRequest.setOrmTools(List.of("MyBatis"));
        updateRequest.setAuth(List.of("JWT"));

        updateRequest.setClouds(List.of("AWS"));
        updateRequest.setOperatingSystems(List.of("Linux"));
        updateRequest.setContainers(List.of("Docker"));
        updateRequest.setDatabases(List.of("PostgreSQL"));
        updateRequest.setWebServers(List.of("nginx"));
        updateRequest.setCiCdTools(List.of("Jenkins"));
        updateRequest.setIacTools(List.of("Terraform"));
        updateRequest.setMonitoringTools(List.of("CloudWatch"));
        updateRequest.setLoggingTools(List.of("CloudWatch Logs"));

        updateRequest.setSourceControls(List.of("Git"));
        updateRequest.setProjectManagements(List.of("Redmine"));
        updateRequest.setCommunicationTools(List.of("Teams"));
        updateRequest.setDocumentationTools(List.of("Confluence"));
        updateRequest.setApiDevelopmentTools(List.of("Postman"));
        updateRequest.setDesignTools(List.of("Figma"));
        updateRequest.setEditors(List.of("VSCode"));
        updateRequest.setDevelopmentEnvironments(List.of("Windows"));

        // 2件目: 新規プロジェクト追加（IDはnull）
        UpdateProjectsRequest.ProjectRequest addRequest = new UpdateProjectsRequest.ProjectRequest();
        addRequest.setId(null);
        addRequest.setCompanyName("会社B");
        addRequest.setStartDate(YearMonth.of(2020, 1));
        addRequest.setEndDate(YearMonth.of(2020, 12));
        addRequest.setIsActive(Boolean.FALSE);
        addRequest.setName("新規プロジェクト");
        addRequest.setOverview("新規プロジェクト概要");
        addRequest.setTeamComp("新規チーム構成");
        addRequest.setRole("新規役割");
        addRequest.setAchievement("新規成果");
        // 工程
        addRequest.setRequirements(Boolean.TRUE);
        addRequest.setBasicDesign(Boolean.FALSE);
        addRequest.setDetailedDesign(Boolean.TRUE);
        addRequest.setImplementation(Boolean.TRUE);
        addRequest.setIntegrationTest(Boolean.TRUE);
        addRequest.setSystemTest(Boolean.FALSE);
        addRequest.setMaintenance(Boolean.FALSE);
        // TechStack
        addRequest.setFrontendLanguages(List.of("JavaScript"));
        addRequest.setFrontendFrameworks(List.of("Vue"));
        addRequest.setFrontendLibraries(List.of());
        addRequest.setFrontendBuildTools(List.of("Vite"));
        addRequest.setFrontendPackageManagers(List.of("yarn"));
        addRequest.setFrontendLinters(List.of());
        addRequest.setFrontendFormatters(List.of());
        addRequest.setFrontendTestingTools(List.of());

        addRequest.setBackendLanguages(List.of("Kotlin"));
        addRequest.setBackendFrameworks(List.of("Spring Boot"));
        addRequest.setBackendLibraries(List.of());
        addRequest.setBackendBuildTools(List.of("Gradle"));
        addRequest.setBackendPackageManagers(List.of("npm"));
        addRequest.setBackendLinters(List.of());
        addRequest.setBackendFormatters(List.of());
        addRequest.setBackendTestingTools(List.of());
        addRequest.setOrmTools(List.of("Hibernate"));
        addRequest.setAuth(List.of("OAuth2"));

        addRequest.setClouds(List.of("GCP"));
        addRequest.setOperatingSystems(List.of("Linux"));
        addRequest.setContainers(List.of("Docker"));
        addRequest.setDatabases(List.of("MySQL"));
        addRequest.setWebServers(List.of("Apache"));
        addRequest.setCiCdTools(List.of("GitHub Actions"));
        addRequest.setIacTools(List.of());
        addRequest.setMonitoringTools(List.of());
        addRequest.setLoggingTools(List.of());

        addRequest.setSourceControls(List.of("GitHub"));
        addRequest.setProjectManagements(List.of("Jira"));
        addRequest.setCommunicationTools(List.of("Slack"));
        addRequest.setDocumentationTools(List.of("Confluence"));
        addRequest.setApiDevelopmentTools(List.of("Insomnia"));
        addRequest.setDesignTools(List.of("Figma"));
        addRequest.setEditors(List.of("IntelliJ"));
        addRequest.setDevelopmentEnvironments(List.of("macOS"));

        UpdateProjectsRequest request = new UpdateProjectsRequest(List.of(updateRequest, addRequest));

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        ResumeInfoUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID, request);

        // repository.find に渡された引数を検証
        ArgumentCaptor<UUID> findCaptor = ArgumentCaptor.forClass(UUID.class);
        verify(repository).find(findCaptor.capture());
        assertThat(findCaptor.getValue()).isEqualTo(RESUME_ID);

        // save() に渡された Resume をキャプチャ
        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        // プロジェクト件数: 既存1件更新＋新規1件追加、もう1件は削除されて合計2件
        assertThat(saved.getProjects()).hasSize(2);

        // 既存プロジェクト1が更新されていることを検証
        Project updatedProject1 = saved.getProjects().stream()
                .filter(p -> p.getId().equals(originalProject1.getId()))
                .findFirst()
                .orElseThrow();
        assertThat(updatedProject1.getName()).isEqualTo("更新後プロジェクト");
        assertThat(updatedProject1.getOverview()).isEqualTo("更新後概要");
        assertThat(updatedProject1.getTeamComp()).isEqualTo("更新後チーム構成");
        assertThat(updatedProject1.getRole()).isEqualTo("更新後役割");
        assertThat(updatedProject1.getAchievement()).isEqualTo("更新後成果");

        // 新規追加されたプロジェクトが存在することを検証（プロジェクト名で判定）
        Project addedProject = saved.getProjects().stream()
                .filter(p -> "新規プロジェクト".equals(p.getName()))
                .findFirst()
                .orElseThrow();
        assertThat(addedProject.getCompanyName().getValue()).isEqualTo("会社B");
        assertThat(addedProject.getPeriod().getStartDate()).isEqualTo(YearMonth.of(2020, 1));
        assertThat(addedProject.getPeriod().getEndDate()).isEqualTo(YearMonth.of(2020, 12));

        // 削除対象だった既存プロジェクト（更新対象以外）が存在しないことを検証
        UUID originalProject2Id = resume.getProjects().stream()
                .map(Project::getId)
                .filter(id -> !id.equals(originalProject1.getId()))
                .findFirst()
                .orElseThrow();
        assertThat(saved.getProjects().stream()
                .noneMatch(p -> p.getId().equals(originalProject2Id))).isTrue();

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
        UpdateProjectsRequest request = new UpdateProjectsRequest(List.of());

        // モック準備（対象の職務経歴書が存在しない）
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書のプロジェクトを更新しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // リクエスト準備
        UpdateProjectsRequest.ProjectRequest requestProject = new UpdateProjectsRequest.ProjectRequest();
        requestProject.setId(null);
        requestProject.setCompanyName("会社A");
        requestProject.setStartDate(YearMonth.of(2018, 1));
        requestProject.setEndDate(YearMonth.of(2018, 12));
        requestProject.setIsActive(Boolean.FALSE);
        requestProject.setName("ダミープロジェクト");
        requestProject.setOverview("ダミー概要");
        requestProject.setTeamComp("ダミーチーム構成");
        requestProject.setRole("ダミー役割");
        requestProject.setAchievement("ダミー成果");
        requestProject.setRequirements(Boolean.TRUE);
        requestProject.setBasicDesign(Boolean.FALSE);
        requestProject.setDetailedDesign(Boolean.FALSE);
        requestProject.setImplementation(Boolean.TRUE);
        requestProject.setIntegrationTest(Boolean.FALSE);
        requestProject.setSystemTest(Boolean.FALSE);
        requestProject.setMaintenance(Boolean.FALSE);

        UpdateProjectsRequest request = new UpdateProjectsRequest(List.of(requestProject));

        // 職務経歴書（所有者は別ユーザー）を準備
        Resume resume = buildResumeWithProjects(OTHER_USER_ID);

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("更新対象のプロジェクトが存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // リクエスト準備（存在しないIDを指定）
        UpdateProjectsRequest.ProjectRequest requestProject = new UpdateProjectsRequest.ProjectRequest();
        requestProject.setId(UUID.fromString("99999999-9999-9999-9999-999999999999"));
        requestProject.setCompanyName("会社A");
        requestProject.setStartDate(YearMonth.of(2018, 1));
        requestProject.setEndDate(YearMonth.of(2018, 12));
        requestProject.setIsActive(Boolean.FALSE);
        requestProject.setName("存在しないプロジェクト更新");
        requestProject.setOverview("ダミー概要");
        requestProject.setTeamComp("ダミーチーム構成");
        requestProject.setRole("ダミー役割");
        requestProject.setAchievement("ダミー成果");
        requestProject.setRequirements(Boolean.TRUE);
        requestProject.setBasicDesign(Boolean.FALSE);
        requestProject.setDetailedDesign(Boolean.FALSE);
        requestProject.setImplementation(Boolean.TRUE);
        requestProject.setIntegrationTest(Boolean.FALSE);
        requestProject.setSystemTest(Boolean.FALSE);
        requestProject.setMaintenance(Boolean.FALSE);

        UpdateProjectsRequest request = new UpdateProjectsRequest(List.of(requestProject));

        // 既存の職務経歴書とプロジェクトを準備
        Resume resume = buildResumeWithProjects(USER_ID);

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("更新対象の職務内容情報が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("空配列が送信された場合、既存のプロジェクトがすべて削除される")
    void test5() {
        // 既存の職務経歴書とプロジェクトを準備（プロジェクト2件）
        Resume resume = buildResumeWithProjects(USER_ID);
        assertThat(resume.getProjects()).hasSize(2);

        // リクエスト準備（空配列）
        UpdateProjectsRequest request = new UpdateProjectsRequest(List.of());

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        useCase.execute(USER_ID, RESUME_ID, request);

        // save() に渡された Resume をキャプチャ
        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        // すべて削除されていることを検証
        assertThat(saved.getProjects()).isEmpty();
    }

    @Test
    @DisplayName("プロジェクトリストがnullの場合、NullPointerExceptionがスローされる")
    void test6() {
        // 既存の職務経歴書を準備
        Resume resume = buildResumeWithProjects(USER_ID);

        // リクエスト準備（プロジェクトリストがnull）
        UpdateProjectsRequest request = new UpdateProjectsRequest(null);

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(NullPointerException.class);

        // findは呼ばれるが、saveは呼ばれないことを検証
        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    /**
     * 職歴2件・プロジェクト2件を持つ職務経歴書を作成するヘルパーメソッド
     */
    private Resume buildResumeWithProjects(UUID ownerId) {
        Notification notification = new Notification();

        // 職務経歴書本体を再構築
        ResumeName resumeName = ResumeName.create(notification, RESUME_NAME);
        FullName fullName = FullName.create(notification, LAST_NAME, FIRST_NAME);

        // 職歴（プロジェクトで使用する会社名に対応させる）
        CompanyName companyA = CompanyName.create(notification, "会社A");
        Period careerPeriodA = Period.create(notification, YearMonth.of(2017, 1), YearMonth.of(2019, 12), false);
        var careerA = com.example.keirekipro.domain.model.resume.Career.create(notification, companyA, careerPeriodA);

        CompanyName companyB = CompanyName.create(notification, "会社B");
        Period careerPeriodB = Period.create(notification, YearMonth.of(2019, 1), YearMonth.of(2021, 12), false);
        var careerB = com.example.keirekipro.domain.model.resume.Career.create(notification, companyB, careerPeriodB);

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
                notification,
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
                notification,
                companyB,
                YearMonth.of(2020, 1),
                YearMonth.of(2020, 12),
                false,
                "プロジェクト2",
                "概要2",
                "チーム2",
                "役割2",
                "成果2");

        // ドメインルール（職歴に存在する会社名か）を通した形で追加
        Resume resumeWithProject1 = base.addProject(notification, project1);
        return resumeWithProject1.addProject(notification, project2);
    }

    /**
     * テスト用プロジェクト生成ヘルパー
     */
    private Project createProject(
            Notification notification,
            CompanyName companyName,
            YearMonth start,
            YearMonth end,
            boolean isActive,
            String name,
            String overview,
            String teamComp,
            String role,
            String achievement) {

        Period period = Period.create(notification, start, end, isActive);

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
                notification,
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
