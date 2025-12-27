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

import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateCertificationRequest;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.UpdateCertificationUseCase;
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
class UpdateCertificationUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private UpdateCertificationUseCase useCase;

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
    @DisplayName("資格を更新できる")
    void test1() {
        // 既存の職務経歴書と資格を準備
        Resume resume = buildResumeWithCertifications(USER_ID);

        // リクエスト準備
        UpdateCertificationRequest request = new UpdateCertificationRequest(
                "更新後資格",
                YearMonth.of(2020, 10));

        // 更新対象IDは、並び順に依存しないよう資格名で特定する
        UUID certificationId = resume.getCertifications().stream()
                .filter(c -> "資格A".equals(c.getName()))
                .map(Certification::getId)
                .findFirst()
                .orElseThrow();

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        ResumeInfoUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID, certificationId, request);

        // repository.find に渡された引数を検証
        ArgumentCaptor<UUID> findCaptor = ArgumentCaptor.forClass(UUID.class);
        verify(repository).find(findCaptor.capture());
        assertThat(findCaptor.getValue()).isEqualTo(RESUME_ID);

        // save() に渡された Resume をキャプチャ
        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        // 資格件数は変わらない（更新のみ）
        assertThat(saved.getCertifications()).hasSize(2);

        // 更新対象が更新されていることを検証
        Certification updated = saved.getCertifications().stream()
                .filter(c -> c.getId().equals(certificationId))
                .findFirst()
                .orElseThrow();

        assertThat(updated.getName()).isEqualTo("更新後資格");
        assertThat(updated.getDate()).isEqualTo(YearMonth.of(2020, 10));

        // 他の資格が保持されていることを検証（資格B）
        assertThat(saved.getCertifications().stream()
                .anyMatch(c -> "資格B".equals(c.getName()))).isTrue();

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
        UpdateCertificationRequest request = new UpdateCertificationRequest(
                "更新後資格",
                YearMonth.of(2020, 10));

        // モック準備（対象の職務経歴書が存在しない）
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        // 実行＆検証
        UUID certificationId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, certificationId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書の資格を更新しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // 職務経歴書（所有者は別ユーザー）を準備
        Resume resume = buildResumeWithCertifications(OTHER_USER_ID);

        // リクエスト準備
        UpdateCertificationRequest request = new UpdateCertificationRequest(
                "更新後資格",
                YearMonth.of(2020, 10));

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        UUID certificationId = resume.getCertifications().stream()
                .map(Certification::getId)
                .findFirst()
                .orElseThrow();

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, certificationId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("更新対象の資格が存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // 既存の職務経歴書を準備
        Resume resume = buildResumeWithCertifications(USER_ID);

        // リクエスト準備
        UpdateCertificationRequest request = new UpdateCertificationRequest(
                "存在しない資格更新",
                YearMonth.of(2020, 1));

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        UUID missingCertificationId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, missingCertificationId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("対象の資格が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    /**
     * 資格2件を持つ職務経歴書を作成するヘルパーメソッド
     */
    private Resume buildResumeWithCertifications(UUID ownerId) {
        ErrorCollector errorCollector = new ErrorCollector();

        // 職務経歴書本体を再構築
        ResumeName resumeName = ResumeName.create(errorCollector, RESUME_NAME);
        FullName fullName = FullName.create(errorCollector, LAST_NAME, FIRST_NAME);

        Resume base = Resume.reconstruct(
                RESUME_ID,
                ownerId,
                resumeName,
                DATE,
                fullName,
                CREATED_AT,
                UPDATED_AT,
                List.of(), // careers
                List.of(), // projects
                List.of(), // certifications
                List.of(), // portfolios
                List.of(), // snsPlatforms
                List.of() // selfPromotions
        );

        // 資格1
        Certification certification1 = Certification.create(
                errorCollector,
                "資格A",
                YearMonth.of(2018, 3));
        Resume resumeWithCertification1 = base.addCertification(errorCollector, certification1);

        // 資格2
        Certification certification2 = Certification.create(
                errorCollector,
                "資格B",
                YearMonth.of(2019, 7));

        return resumeWithCertification1.addCertification(errorCollector, certification2);
    }
}
