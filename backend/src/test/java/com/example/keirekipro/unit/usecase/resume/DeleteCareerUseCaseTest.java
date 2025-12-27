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

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.DeleteCareerUseCase;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class DeleteCareerUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private DeleteCareerUseCase useCase;

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
    @DisplayName("職歴を削除できる")
    void test1() {
        Resume resume = buildResumeWithCareers(USER_ID);
        UUID careerId = resume.getCareers().get(0).getId();

        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        useCase.execute(USER_ID, RESUME_ID, careerId);

        verify(repository).find(RESUME_ID);

        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        assertThat(saved.getCareers()).hasSize(1);
        assertThat(saved.getCareers().stream().anyMatch(c -> c.getId().equals(careerId))).isFalse();
    }

    @Test
    @DisplayName("対象の職務経歴書が存在しない場合、UseCaseExceptionがスローされる")
    void test2() {
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        UUID careerId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, careerId))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書の職歴を削除しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        Resume resume = buildResumeWithCareers(OTHER_USER_ID);
        UUID careerId = resume.getCareers().get(0).getId();

        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, careerId))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("削除対象の職歴が存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        Resume resume = buildResumeWithCareers(USER_ID);

        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        UUID missingCareerId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, missingCareerId))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("対象の職歴が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    private Resume buildResumeWithCareers(UUID ownerId) {
        ErrorCollector errorCollector = new ErrorCollector();

        ResumeName resumeName = ResumeName.create(errorCollector, RESUME_NAME);
        FullName fullName = FullName.create(errorCollector, LAST_NAME, FIRST_NAME);

        CompanyName companyA = CompanyName.create(errorCollector, "会社A");
        Period periodA = Period.create(errorCollector, YearMonth.of(2017, 1), YearMonth.of(2019, 12), false);
        Career careerA = Career.create(errorCollector, companyA, periodA);

        CompanyName companyB = CompanyName.create(errorCollector, "会社B");
        Period periodB = Period.create(errorCollector, YearMonth.of(2020, 1), YearMonth.of(2021, 12), false);
        Career careerB = Career.create(errorCollector, companyB, periodB);

        return Resume.reconstruct(
                RESUME_ID,
                ownerId,
                resumeName,
                DATE,
                fullName,
                CREATED_AT,
                UPDATED_AT,
                List.of(careerA, careerB), // careers
                List.of(), // projects
                List.of(), // certifications
                List.of(), // portfolios
                List.of(), // snsPlatforms
                List.of() // selfPromotions
        );
    }
}
