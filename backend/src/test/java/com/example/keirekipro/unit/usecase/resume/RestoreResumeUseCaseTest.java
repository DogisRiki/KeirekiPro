package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeNameDuplicationCheckService;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.presentation.resume.dto.RestoreResumeRequest;
import com.example.keirekipro.usecase.resume.RestoreResumeUseCase;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.resume.policy.ResumeBackupVersion;
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
class RestoreResumeUseCaseTest {

    @Mock
    private ResumeLimitChecker resumeLimitChecker;

    @Mock
    private ResumeNameDuplicationCheckService resumeNameDuplicationCheckService;

    @Mock
    private ResumeRepository resumeRepository;

    @InjectMocks
    private RestoreResumeUseCase useCase;

    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final String RESUME_NAME = "職務経歴書1";
    private static final LocalDate DATE = LocalDate.of(2025, 1, 1);
    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";

    @Test
    @DisplayName("正常にリストアできる")
    void test1() {
        // リクエスト準備
        RestoreResumeRequest request = buildValidRequest();

        // モック設定（上限OK、重複なし）
        doNothing().when(resumeLimitChecker).checkResumeCreateAllowed(USER_ID);
        doNothing().when(resumeNameDuplicationCheckService).execute(eq(USER_ID), any(ResumeName.class));

        // 実行
        ArgumentCaptor<Resume> captor = ArgumentCaptor.forClass(Resume.class);
        ResumeInfoUseCaseDto actual = useCase.execute(USER_ID, request);

        // 検証
        verify(resumeLimitChecker).checkResumeCreateAllowed(USER_ID);
        verify(resumeNameDuplicationCheckService).execute(eq(USER_ID), any(ResumeName.class));
        verify(resumeRepository).save(captor.capture());

        Resume saved = captor.getValue();

        // ルートエンティティの基本項目検証
        assertThat(saved.getId()).isNotNull();
        assertThat(saved.getUserId()).isEqualTo(USER_ID);
        assertThat(saved.getName().getValue()).isEqualTo(RESUME_NAME);
        assertThat(saved.getDate()).isEqualTo(DATE);
        assertThat(saved.getFullName().getLastName()).isEqualTo(LAST_NAME);
        assertThat(saved.getFullName().getFirstName()).isEqualTo(FIRST_NAME);

        // サブエンティティ（代表項目）の検証
        assertThat(saved.getCareers()).hasSize(1);
        assertThat(saved.getCareers().get(0).getCompanyName().getValue()).isEqualTo("Company");
        assertThat(saved.getCareers().get(0).getPeriod().getStartDate()).isEqualTo(YearMonth.of(2020, 1));
        assertThat(saved.getCareers().get(0).getPeriod().getEndDate()).isNull();
        assertThat(saved.getCareers().get(0).getPeriod().isActive()).isTrue();

        assertThat(saved.getProjects()).hasSize(1);
        assertThat(saved.getProjects().get(0).getCompanyName().getValue()).isEqualTo("Company");
        assertThat(saved.getProjects().get(0).getName()).isEqualTo("Project");
        assertThat(saved.getProjects().get(0).getProcess().isRequirements()).isTrue();

        assertThat(saved.getCertifications()).hasSize(1);
        assertThat(saved.getCertifications().get(0).getName()).isEqualTo("基本情報技術者");
        assertThat(saved.getCertifications().get(0).getDate()).isEqualTo(YearMonth.of(2022, 1));

        assertThat(saved.getPortfolios()).hasSize(1);
        assertThat(saved.getPortfolios().get(0).getName()).isEqualTo("PF1");
        assertThat(saved.getPortfolios().get(0).getLink().getValue()).isEqualTo("https://portfolio.example");

        assertThat(saved.getSnsPlatforms()).hasSize(1);
        assertThat(saved.getSnsPlatforms().get(0).getName()).isEqualTo("X");
        assertThat(saved.getSnsPlatforms().get(0).getLink().getValue()).isEqualTo("https://x.example");

        assertThat(saved.getSelfPromotions()).hasSize(1);
        assertThat(saved.getSelfPromotions().get(0).getTitle()).isEqualTo("PR1");
        assertThat(saved.getSelfPromotions().get(0).getContent()).isEqualTo("content");

        // save()で受け取ったResumeからDTOを組み立て、それを比較
        ResumeInfoUseCaseDto expected = ResumeInfoUseCaseDto.convertToUseCaseDto(saved);
        assertThat(actual)
                .usingRecursiveComparison()
                .isEqualTo(expected);
    }

    @Test
    @DisplayName("バックアップバージョンがサポート外の場合、UseCaseExceptionがスローされ後続処理が行われない")
    void test2() {
        // リクエスト準備（バージョン不正）
        RestoreResumeRequest request = buildValidRequest();
        request.setVersion("unsupported-version");

        assertThatThrownBy(() -> useCase.execute(USER_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("サポートされていないバックアップバージョンです。");

        verify(resumeLimitChecker, never()).checkResumeCreateAllowed(any());
        verify(resumeNameDuplicationCheckService, never()).execute(any(), any());
        verify(resumeRepository, never()).save(any());
    }

    @Test
    @DisplayName("職務経歴書が上限枚数である場合、UseCaseExceptionがスローされ後続処理が行われない")
    void test3() {
        RestoreResumeRequest request = buildValidRequest();

        doThrow(new UseCaseException("上限"))
                .when(resumeLimitChecker).checkResumeCreateAllowed(USER_ID);

        assertThatThrownBy(() -> useCase.execute(USER_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("上限");

        verify(resumeLimitChecker).checkResumeCreateAllowed(USER_ID);
        verify(resumeNameDuplicationCheckService, never()).execute(any(), any());
        verify(resumeRepository, never()).save(any());
    }

    @Test
    @DisplayName("職務経歴書名が重複していた場合、DomainExceptionがスローされ後続処理が行われない")
    void test4() {
        RestoreResumeRequest request = buildValidRequest();

        doNothing().when(resumeLimitChecker).checkResumeCreateAllowed(USER_ID);
        doThrow(new DomainException("この職務経歴書名は既に登録されています。"))
                .when(resumeNameDuplicationCheckService).execute(eq(USER_ID), any(ResumeName.class));

        assertThatThrownBy(() -> useCase.execute(USER_ID, request))
                .isInstanceOf(DomainException.class)
                .hasMessage("この職務経歴書名は既に登録されています。");

        verify(resumeLimitChecker).checkResumeCreateAllowed(USER_ID);
        verify(resumeNameDuplicationCheckService).execute(eq(USER_ID), any(ResumeName.class));
        verify(resumeRepository, never()).save(any());
    }

    @Test
    @DisplayName("バックアップファイルが破損または改ざんされている場合、UseCaseExceptionがスローされる")
    void test5() {
        // リクエスト準備（Periodが不正：endDate < startDate）
        RestoreResumeRequest request = buildInvalidRequest();

        doNothing().when(resumeLimitChecker).checkResumeCreateAllowed(USER_ID);
        doNothing().when(resumeNameDuplicationCheckService).execute(eq(USER_ID), any(ResumeName.class));

        assertThatThrownBy(() -> useCase.execute(USER_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("バックアップファイルが不正なためリストアできません。\n別のバックアップファイルでお試しください。");

        verify(resumeLimitChecker).checkResumeCreateAllowed(USER_ID);
        verify(resumeNameDuplicationCheckService).execute(eq(USER_ID), any(ResumeName.class));
        verify(resumeRepository, never()).save(any());
    }

    private static RestoreResumeRequest buildValidRequest() {
        RestoreResumeRequest.CareerDto career = new RestoreResumeRequest.CareerDto(
                "Company",
                YearMonth.of(2020, 1),
                null,
                true);

        RestoreResumeRequest.ProcessDto process = new RestoreResumeRequest.ProcessDto(
                true, true, true, true, true, true, true);

        RestoreResumeRequest.TechStackDto techStack = new RestoreResumeRequest.TechStackDto(
                new RestoreResumeRequest.FrontendDto(
                        List.of("TypeScript", "JavaScript"),
                        List.of("React"),
                        List.of("Redux"),
                        List.of("Vite"),
                        List.of("npm"),
                        List.of("ESLint"),
                        List.of("Prettier"),
                        List.of("Jest")),
                new RestoreResumeRequest.BackendDto(
                        List.of("Java"),
                        List.of("Spring Boot"),
                        List.of("Jackson"),
                        List.of("Gradle"),
                        List.of("Maven"),
                        List.of("Checkstyle"),
                        List.of("Spotless"),
                        List.of("JUnit"),
                        List.of("MyBatis"),
                        List.of("JWT")),
                new RestoreResumeRequest.InfrastructureDto(
                        List.of("AWS"),
                        List.of("Linux"),
                        List.of("Docker"),
                        List.of("PostgreSQL"),
                        List.of("Nginx"),
                        List.of("GitHub Actions"),
                        List.of("Terraform"),
                        List.of("CloudWatch"),
                        List.of("OpenSearch")),
                new RestoreResumeRequest.ToolsDto(
                        List.of("Git"),
                        List.of("Jira"),
                        List.of("Slack"),
                        List.of("Confluence"),
                        List.of("Postman"),
                        List.of("Figma"),
                        List.of("IntelliJ IDEA"),
                        List.of("Docker Compose")));

        RestoreResumeRequest.ProjectDto project = new RestoreResumeRequest.ProjectDto(
                "Company",
                YearMonth.of(2021, 1),
                null,
                true,
                "Project",
                "Overview",
                "Team",
                "Role",
                "Achievement",
                process,
                techStack);

        RestoreResumeRequest.CertificationDto cert = new RestoreResumeRequest.CertificationDto(
                "基本情報技術者",
                YearMonth.of(2022, 1));

        RestoreResumeRequest.PortfolioDto portfolio = new RestoreResumeRequest.PortfolioDto(
                "PF1",
                "overview",
                "tech",
                "https://portfolio.example");

        RestoreResumeRequest.SnsPlatformDto sns = new RestoreResumeRequest.SnsPlatformDto(
                "X",
                "https://x.example");

        RestoreResumeRequest.SelfPromotionDto sp = new RestoreResumeRequest.SelfPromotionDto(
                "PR1",
                "content");

        RestoreResumeRequest.ResumeDto resume = new RestoreResumeRequest.ResumeDto(
                RESUME_NAME,
                DATE,
                LAST_NAME,
                FIRST_NAME,
                List.of(career),
                List.of(project),
                List.of(cert),
                List.of(portfolio),
                List.of(sns),
                List.of(sp));

        return new RestoreResumeRequest(
                ResumeBackupVersion.SUPPORTED_VERSION,
                Instant.now(),
                resume);
    }

    private static RestoreResumeRequest buildInvalidRequest() {
        // endDate < startDate を作ってPeriod.createのDomainExceptionを誘発する
        RestoreResumeRequest.CareerDto invalidCareer = new RestoreResumeRequest.CareerDto(
                "Company",
                YearMonth.of(2025, 2),
                YearMonth.of(2024, 1),
                false);

        RestoreResumeRequest.ResumeDto resume = new RestoreResumeRequest.ResumeDto(
                RESUME_NAME,
                DATE,
                LAST_NAME,
                FIRST_NAME,
                List.of(invalidCareer),
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of());

        return new RestoreResumeRequest(
                ResumeBackupVersion.SUPPORTED_VERSION,
                Instant.now(),
                resume);
    }
}
