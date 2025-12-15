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
import com.example.keirekipro.presentation.resume.dto.UpdateCareerRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.UpdateCareerUseCase;
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
class UpdateCareerUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private UpdateCareerUseCase useCase;

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
    @DisplayName("職歴を更新できる")
    void test1() {
        // 既存の職務経歴書と職歴を準備
        Resume resume = buildResumeWithCareers(USER_ID);

        // リクエスト準備
        UpdateCareerRequest request = new UpdateCareerRequest(
                "更新後会社",
                YearMonth.of(2018, 1),
                YearMonth.of(2018, 12),
                Boolean.FALSE);

        // 更新対象IDは、並び順に依存しないよう会社名で特定する
        UUID careerId = resume.getCareers().stream()
                .filter(c -> "会社A".equals(c.getCompanyName().getValue()))
                .map(Career::getId)
                .findFirst()
                .orElseThrow();

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        ResumeInfoUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID, careerId, request);

        // repository.find に渡された引数を検証
        ArgumentCaptor<UUID> findCaptor = ArgumentCaptor.forClass(UUID.class);
        verify(repository).find(findCaptor.capture());
        assertThat(findCaptor.getValue()).isEqualTo(RESUME_ID);

        // save() に渡された Resume をキャプチャ
        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        // 職歴件数は変わらない（更新のみ）
        assertThat(saved.getCareers()).hasSize(2);

        // 更新対象が更新されていることを検証
        Career updatedCareer = saved.getCareers().stream()
                .filter(c -> c.getId().equals(careerId))
                .findFirst()
                .orElseThrow();

        assertThat(updatedCareer.getCompanyName().getValue()).isEqualTo("更新後会社");
        assertThat(updatedCareer.getPeriod().getStartDate()).isEqualTo(YearMonth.of(2018, 1));
        assertThat(updatedCareer.getPeriod().getEndDate()).isEqualTo(YearMonth.of(2018, 12));
        assertThat(updatedCareer.getPeriod().isActive()).isFalse();

        // 他の職歴が保持されていることを検証（会社B）
        assertThat(saved.getCareers().stream()
                .anyMatch(c -> "会社B".equals(c.getCompanyName().getValue()))).isTrue();

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
        UpdateCareerRequest request = new UpdateCareerRequest(
                "更新後会社",
                YearMonth.of(2018, 1),
                YearMonth.of(2018, 12),
                Boolean.FALSE);

        // モック準備（対象の職務経歴書が存在しない）
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        // 実行＆検証
        UUID careerId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, careerId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書の職歴を更新しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // 職務経歴書（所有者は別ユーザー）を準備
        Resume resume = buildResumeWithCareers(OTHER_USER_ID);

        // リクエスト準備
        UpdateCareerRequest request = new UpdateCareerRequest(
                "更新後会社",
                YearMonth.of(2018, 1),
                YearMonth.of(2018, 12),
                Boolean.FALSE);

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        UUID careerId = resume.getCareers().stream()
                .map(Career::getId)
                .findFirst()
                .orElseThrow();

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, careerId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("更新対象の職歴が存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // 既存の職務経歴書を準備
        Resume resume = buildResumeWithCareers(USER_ID);

        // リクエスト準備
        UpdateCareerRequest request = new UpdateCareerRequest(
                "存在しない職歴更新",
                YearMonth.of(2020, 1),
                YearMonth.of(2020, 12),
                Boolean.FALSE);

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        UUID missingCareerId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, missingCareerId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("対象の職歴が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    /**
     * 職歴2件を持つ職務経歴書を作成するヘルパーメソッド
     */
    private Resume buildResumeWithCareers(UUID ownerId) {
        Notification notification = new Notification();

        // 職務経歴書本体を再構築（職歴などのリストは空で開始する）
        ResumeName resumeName = ResumeName.create(notification, RESUME_NAME);
        FullName fullName = FullName.create(notification, LAST_NAME, FIRST_NAME);

        Resume base = Resume.reconstruct(
                RESUME_ID,
                ownerId,
                resumeName,
                DATE,
                fullName,
                CREATED_AT,
                UPDATED_AT,
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of());

        // 職歴1（2018年）
        CompanyName company1 = CompanyName.create(notification, "会社A");
        Period period1 = Period.create(notification, YearMonth.of(2018, 1), YearMonth.of(2018, 12), false);
        Career career1 = Career.create(notification, company1, period1);
        Resume resumeWithCareer1 = base.addCareer(notification, career1);

        // 職歴2（2021年）
        CompanyName company2 = CompanyName.create(notification, "会社B");
        Period period2 = Period.create(notification, YearMonth.of(2021, 1), YearMonth.of(2021, 12), false);
        Career career2 = Career.create(notification, company2, period2);

        return resumeWithCareer1.addCareer(notification, career2);
    }
}
