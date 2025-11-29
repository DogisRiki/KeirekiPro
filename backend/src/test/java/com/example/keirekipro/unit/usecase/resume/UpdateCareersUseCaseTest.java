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
import com.example.keirekipro.presentation.resume.dto.UpdateCareersRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.UpdateCareersUseCase;
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
class UpdateCareersUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private UpdateCareersUseCase useCase;

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
    @DisplayName("職歴を追加・更新・削除できる")
    void test1() {
        // 既存の職務経歴書と職歴を準備
        Resume resume = buildResumeWithCareers(USER_ID);
        List<Career> originalCareers = resume.getCareers();
        Career originalCareer1 = originalCareers.get(0);
        Career originalCareer2 = originalCareers.get(1);

        // リクエスト準備
        // 1件目: 既存職歴1を更新
        UpdateCareersRequest.CareerRequest updateRequest = new UpdateCareersRequest.CareerRequest(
                originalCareer1.getId(),
                "更新後会社",
                YearMonth.of(2018, 1),
                YearMonth.of(2018, 12),
                Boolean.FALSE);

        // 2件目: 新規職歴追加（IDはnull）
        // 期間は2020年、会社Bは2021年にしているため重複しない
        UpdateCareersRequest.CareerRequest addRequest = new UpdateCareersRequest.CareerRequest(
                null,
                "新規会社",
                YearMonth.of(2020, 1),
                YearMonth.of(2020, 12),
                Boolean.FALSE);

        UpdateCareersRequest request = new UpdateCareersRequest(List.of(updateRequest, addRequest));

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

        // 職歴の件数: 既存1件更新＋新規1件追加、もう1件は削除されて合計2件
        assertThat(saved.getCareers()).hasSize(2);

        // 既存職歴1が更新されていることを検証
        Career updatedCareer1 = saved.getCareers().stream()
                .filter(c -> c.getId().equals(originalCareer1.getId()))
                .findFirst()
                .orElseThrow();
        assertThat(updatedCareer1.getCompanyName().getValue()).isEqualTo("更新後会社");
        assertThat(updatedCareer1.getPeriod().getStartDate()).isEqualTo(YearMonth.of(2018, 1));
        assertThat(updatedCareer1.getPeriod().getEndDate()).isEqualTo(YearMonth.of(2018, 12));

        // 新規追加された職歴が存在することを検証（会社名で判定）
        Career addedCareer = saved.getCareers().stream()
                .filter(c -> "新規会社".equals(c.getCompanyName().getValue()))
                .findFirst()
                .orElseThrow();
        assertThat(addedCareer.getPeriod().getStartDate()).isEqualTo(YearMonth.of(2020, 1));
        assertThat(addedCareer.getPeriod().getEndDate()).isEqualTo(YearMonth.of(2020, 12));

        // 削除対象だった既存職歴2が存在しないことを検証
        assertThat(saved.getCareers().stream()
                .noneMatch(c -> c.getId().equals(originalCareer2.getId()))).isTrue();

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
        UpdateCareersRequest request = new UpdateCareersRequest(List.of());

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
    @DisplayName("ログインユーザー以外が所有する職務経歴書の職歴を更新しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // 職務経歴書（所有者は別ユーザー）を準備
        Resume resume = buildResumeWithCareers(OTHER_USER_ID);

        // リクエスト準備
        UpdateCareersRequest.CareerRequest requestCareer = new UpdateCareersRequest.CareerRequest(
                null,
                "会社X",
                YearMonth.of(2020, 1),
                YearMonth.of(2020, 12),
                Boolean.FALSE);
        UpdateCareersRequest request = new UpdateCareersRequest(List.of(requestCareer));

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
    @DisplayName("更新対象の職歴が存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // 既存の職務経歴書と職歴を準備
        Resume resume = buildResumeWithCareers(USER_ID);

        // リクエスト準備（存在しないIDを指定）
        UpdateCareersRequest.CareerRequest requestCareer = new UpdateCareersRequest.CareerRequest(
                UUID.fromString("99999999-9999-9999-9999-999999999999"),
                "存在しない職歴更新",
                YearMonth.of(2020, 1),
                YearMonth.of(2020, 12),
                Boolean.FALSE);
        UpdateCareersRequest request = new UpdateCareersRequest(List.of(requestCareer));

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("更新対象の職歴情報が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("空配列が送信された場合、既存の職歴がすべて削除される")
    void test5() {
        // 既存の職務経歴書と職歴を準備（職歴2件）
        Resume resume = buildResumeWithCareers(USER_ID);
        assertThat(resume.getCareers()).hasSize(2);

        // リクエスト準備（空配列）
        UpdateCareersRequest request = new UpdateCareersRequest(List.of());

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        useCase.execute(USER_ID, RESUME_ID, request);

        // save() に渡された Resume をキャプチャ
        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        // すべて削除されていることを検証
        assertThat(saved.getCareers()).isEmpty();
    }

    @Test
    @DisplayName("職歴リストがnullの場合、NullPointerExceptionがスローされる")
    void test6() {
        // 既存の職務経歴書を準備
        Resume resume = buildResumeWithCareers(USER_ID);

        // リクエスト準備（職歴リストがnull）
        UpdateCareersRequest request = new UpdateCareersRequest(null);

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

        // 職歴2（2021年）: 新規会社(2020年)と重複しないように設定
        CompanyName company2 = CompanyName.create(notification, "会社B");
        Period period2 = Period.create(notification, YearMonth.of(2021, 1), YearMonth.of(2021, 12), false);
        Career career2 = Career.create(notification, company2, period2);

        return resumeWithCareer1.addCareer(notification, career2);
    }
}
