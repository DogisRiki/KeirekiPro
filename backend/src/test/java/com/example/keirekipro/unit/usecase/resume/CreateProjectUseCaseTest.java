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
import com.example.keirekipro.usecase.resume.command.CreateProjectCommand;
import com.example.keirekipro.shared.ErrorCollector;
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
        CreateProjectCommand request = buildRequest();

        doNothing().when(checker).checkProjectAddAllowed(RESUME_ID);
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(buildResumeWithCareer(USER_ID)));

        ResumeInfoUseCaseDto actual = useCase.execute(request);

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
        CreateProjectCommand request = buildRequest();

        doNothing().when(checker).checkProjectAddAllowed(RESUME_ID);
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> useCase.execute(request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("対象の職務経歴書データが存在しません。");

        verify(checker).checkProjectAddAllowed(RESUME_ID);
        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書にプロジェクトを作成しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        CreateProjectCommand request = buildRequest();

        doNothing().when(checker).checkProjectAddAllowed(RESUME_ID);
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(buildResumeWithCareer(OTHER_USER_ID)));

        assertThatThrownBy(() -> useCase.execute(request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("対象の職務経歴書データが存在しません。");

        verify(checker).checkProjectAddAllowed(RESUME_ID);
        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("プロジェクトが上限件数である場合、例外がスローされ後続処理が行われない")
    void test4() {
        CreateProjectCommand request = buildRequest();

        doThrow(new UseCaseException("上限")).when(checker).checkProjectAddAllowed(RESUME_ID);

        assertThatThrownBy(() -> useCase.execute(request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("上限");

        verify(checker).checkProjectAddAllowed(RESUME_ID);
        verify(repository, never()).find(any());
        verify(repository, never()).save(any());
    }

    private CreateProjectCommand buildRequest() {
        return new CreateProjectCommand(
                USER_ID,
                RESUME_ID.toString(),
                "会社A",
                YearMonth.of(2018, 1),
                YearMonth.of(2018, 12),
                Boolean.FALSE,
                "プロジェクト1",
                "概要1",
                "チーム1",
                "役割1",
                "成果1",
                Boolean.TRUE,
                Boolean.TRUE,
                Boolean.FALSE,
                Boolean.TRUE,
                Boolean.FALSE,
                Boolean.TRUE,
                Boolean.FALSE,
                List.of("TypeScript"),
                List.of("React"),
                List.of("MUI"),
                List.of("Vite"),
                List.of("npm"),
                List.of("ESLint"),
                List.of("Prettier"),
                List.of("RTL"),
                List.of("Java"),
                List.of("Spring Boot"),
                List.of("MyBatis"),
                List.of("Gradle"),
                List.of("npm"),
                List.of(),
                List.of(),
                List.of("JUnit"),
                List.of("MyBatis"),
                List.of("JWT"),
                List.of("AWS"),
                List.of("Linux"),
                List.of("Docker"),
                List.of("PostgreSQL"),
                List.of("nginx"),
                List.of("Jenkins"),
                List.of("Terraform"),
                List.of("CloudWatch"),
                List.of("CloudWatch Logs"),
                List.of("Git"),
                List.of("Redmine"),
                List.of("Teams"),
                List.of("Confluence"),
                List.of("Postman"),
                List.of("Figma"),
                List.of("VSCode"),
                List.of("Windows"));
    }

    private Resume buildResumeWithCareer(UUID ownerId) {
        ErrorCollector errorCollector = new ErrorCollector();

        ResumeName resumeName = ResumeName.create(errorCollector, RESUME_NAME);
        FullName fullName = FullName.create(errorCollector, LAST_NAME, FIRST_NAME);

        CompanyName companyName = CompanyName.create(errorCollector, "会社A");
        Period period = Period.create(errorCollector, YearMonth.of(2017, 1), YearMonth.of(2019, 12), false);
        Career career = Career.create(errorCollector, companyName, period);

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
                List.of(), // snsPlatforms
                List.of() // selfPromotions
        );
    }
}
