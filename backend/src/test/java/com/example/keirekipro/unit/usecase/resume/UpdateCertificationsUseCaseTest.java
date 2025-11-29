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
import com.example.keirekipro.presentation.resume.dto.UpdateCertificationsRequest;
import com.example.keirekipro.presentation.resume.dto.UpdateCertificationsRequest.CertificationRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.UpdateCertificationsUseCase;
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
class UpdateCertificationsUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private UpdateCertificationsUseCase useCase;

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
    @DisplayName("資格を追加・更新・削除できる")
    void test1() {
        // 既存の職務経歴書と資格を準備
        Resume resume = buildResumeWithCertifications(USER_ID);
        List<Certification> originalCertifications = resume.getCertifications();
        Certification originalCertification1 = originalCertifications.get(0);
        UUID originalCertification2Id = originalCertifications.get(1).getId();

        // リクエスト準備
        // 1件目: 既存資格1を更新
        CertificationRequest updateRequest = new CertificationRequest(
                originalCertification1.getId(),
                "更新後資格",
                YearMonth.of(2019, 5));

        // 2件目: 新規資格追加（IDはnull）
        CertificationRequest addRequest = new CertificationRequest(
                null,
                "新規資格",
                YearMonth.of(2020, 10));

        UpdateCertificationsRequest request = new UpdateCertificationsRequest(List.of(updateRequest, addRequest));

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

        // 資格の件数: 既存1件更新＋新規1件追加、もう1件は削除されて合計2件
        assertThat(saved.getCertifications()).hasSize(2);

        // 既存資格1が更新されていることを検証
        Certification updatedCertification1 = saved.getCertifications().stream()
                .filter(c -> c.getId().equals(originalCertification1.getId()))
                .findFirst()
                .orElseThrow();
        assertThat(updatedCertification1.getName()).isEqualTo("更新後資格");
        assertThat(updatedCertification1.getDate()).isEqualTo(YearMonth.of(2019, 5));

        // 新規追加された資格が存在することを検証（資格名で判定）
        Certification addedCertification = saved.getCertifications().stream()
                .filter(c -> "新規資格".equals(c.getName()))
                .findFirst()
                .orElseThrow();
        assertThat(addedCertification.getDate()).isEqualTo(YearMonth.of(2020, 10));

        // 削除対象だった既存資格2が存在しないことを検証
        assertThat(saved.getCertifications().stream()
                .noneMatch(c -> c.getId().equals(originalCertification2Id))).isTrue();

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
        UpdateCertificationsRequest request = new UpdateCertificationsRequest(List.of());

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
    @DisplayName("ログインユーザー以外が所有する職務経歴書の資格を更新しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // リクエスト準備
        CertificationRequest requestCertification = new CertificationRequest(
                null,
                "ダミー資格",
                YearMonth.of(2020, 1));
        UpdateCertificationsRequest request = new UpdateCertificationsRequest(List.of(requestCertification));

        // 職務経歴書（所有者は別ユーザー）を準備
        Resume resume = buildResumeWithCertifications(OTHER_USER_ID);

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
    @DisplayName("更新対象の資格が存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // リクエスト準備（存在しないIDを指定）
        CertificationRequest requestCertification = new CertificationRequest(
                UUID.fromString("99999999-9999-9999-9999-999999999999"),
                "存在しない資格更新",
                YearMonth.of(2020, 1));
        UpdateCertificationsRequest request = new UpdateCertificationsRequest(List.of(requestCertification));

        // 既存の職務経歴書と資格を準備
        Resume resume = buildResumeWithCertifications(USER_ID);

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("更新対象の資格情報が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("空配列が送信された場合、既存の資格がすべて削除される")
    void test5() {
        // 既存の職務経歴書と資格を準備（資格2件）
        Resume resume = buildResumeWithCertifications(USER_ID);
        assertThat(resume.getCertifications()).hasSize(2);

        // リクエスト準備
        UpdateCertificationsRequest request = new UpdateCertificationsRequest(List.of());

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        useCase.execute(USER_ID, RESUME_ID, request);

        // save() に渡された Resume をキャプチャ
        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        // すべて削除されていることを検証
        assertThat(saved.getCertifications()).isEmpty();
    }

    @Test
    @DisplayName("資格リストがnullの場合、NullPointerExceptionがスローされる")
    void test6() {
        // 既存の職務経歴書を準備
        Resume resume = buildResumeWithCertifications(USER_ID);

        // リクエスト準備（資格リストがnull）
        UpdateCertificationsRequest request = new UpdateCertificationsRequest(null);

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
     * 資格2件を持つ職務経歴書を作成するヘルパーメソッド
     */
    private Resume buildResumeWithCertifications(UUID ownerId) {
        Notification notification = new Notification();

        // 職務経歴書本体を再構築
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
                List.of(), // careers
                List.of(), // projects
                List.of(), // certifications
                List.of(), // portfolios
                List.of(), // socialLinks
                List.of() // selfPromotions
        );

        // 資格1
        Certification certification1 = Certification.create(
                notification,
                "資格A",
                YearMonth.of(2018, 3));
        Resume resumeWithCertification1 = base.addCertification(notification, certification1);

        // 資格2
        Certification certification2 = Certification.create(
                notification,
                "資格B",
                YearMonth.of(2019, 7));

        return resumeWithCertification1.addCertification(notification, certification2);
    }
}
