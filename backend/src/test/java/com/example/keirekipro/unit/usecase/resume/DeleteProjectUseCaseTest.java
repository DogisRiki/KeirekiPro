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
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.DeleteProjectUseCase;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class DeleteProjectUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private DeleteProjectUseCase useCase;

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
    @DisplayName("プロジェクトを削除できる")
    void test1() {
        Resume resume = buildResumeWithProjects(USER_ID);
        UUID projectId = resume.getProjects().get(0).getId();

        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        useCase.execute(USER_ID, RESUME_ID, projectId);

        verify(repository).find(RESUME_ID);

        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        assertThat(saved.getProjects()).hasSize(1);
        assertThat(saved.getProjects().stream().anyMatch(p -> p.getId().equals(projectId))).isFalse();
    }

    @Test
    @DisplayName("対象の職務経歴書が存在しない場合、UseCaseExceptionがスローされる")
    void test2() {
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        UUID projectId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, projectId))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書のプロジェクトを削除しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        Resume resume = buildResumeWithProjects(OTHER_USER_ID);
        UUID projectId = resume.getProjects().get(0).getId();

        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, projectId))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("削除対象のプロジェクトが存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        Resume resume = buildResumeWithProjects(USER_ID);

        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        UUID missingId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, missingId))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("対象のプロジェクトが存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    private Resume buildResumeWithProjects(UUID ownerId) {
        ErrorCollector errorCollector = new ErrorCollector();

        ResumeName resumeName = ResumeName.create(errorCollector, RESUME_NAME);
        FullName fullName = FullName.create(errorCollector, LAST_NAME, FIRST_NAME);

        CompanyName companyA = CompanyName.create(errorCollector, "会社A");
        Period periodA = Period.create(errorCollector, YearMonth.of(2018, 1), YearMonth.of(2018, 12), false);

        Project.Process process = Project.Process.create(true, true, false, true, false, true, false);

        TechStack techStack = TechStack.create(
                TechStack.Frontend.create(
                        List.of("TypeScript"),
                        List.of("React"),
                        List.of("MUI"),
                        List.of("Vite"),
                        List.of("npm"),
                        List.of("ESLint"),
                        List.of("Prettier"),
                        List.of("RTL")),
                TechStack.Backend.create(
                        List.of("Java"),
                        List.of("Spring Boot"),
                        List.of("MyBatis"),
                        List.of("Gradle"),
                        List.of("npm"),
                        List.of(),
                        List.of(),
                        List.of("JUnit"),
                        List.of("MyBatis"),
                        List.of("JWT")),
                TechStack.Infrastructure.create(
                        List.of("AWS"),
                        List.of("Linux"),
                        List.of("Docker"),
                        List.of("PostgreSQL"),
                        List.of("nginx"),
                        List.of("Jenkins"),
                        List.of("Terraform"),
                        List.of("CloudWatch"),
                        List.of("CloudWatch Logs")),
                TechStack.Tools.create(
                        List.of("Git"),
                        List.of("Redmine"),
                        List.of("Teams"),
                        List.of("Confluence"),
                        List.of("Postman"),
                        List.of("Figma"),
                        List.of("VSCode"),
                        List.of("Windows")));

        Project p1 = Project.create(errorCollector, companyA, periodA, "プロジェクト1", "概要1", "チーム1", "役割1", "成果1", process,
                techStack);
        Project p2 = Project.create(errorCollector, companyA, periodA, "プロジェクト2", "概要2", "チーム2", "役割2", "成果2", process,
                techStack);

        return Resume.reconstruct(
                RESUME_ID,
                ownerId,
                resumeName,
                DATE,
                fullName,
                CREATED_AT,
                UPDATED_AT,
                List.of(), // careers
                List.of(p1, p2), // projects
                List.of(), // certifications
                List.of(), // portfolios
                List.of(), // snsPlatforms
                List.of() // selfPromotions
        );
    }
}
