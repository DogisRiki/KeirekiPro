package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateSelfPromotionsRequest;
import com.example.keirekipro.presentation.resume.dto.UpdateSelfPromotionsRequest.SelfPromotionRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.UpdateSelfPromotionsUseCase;
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
class UpdateSelfPromotionsUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private UpdateSelfPromotionsUseCase useCase;

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
    @DisplayName("自己PRを追加・更新・削除できる")
    void test1() {
        // 既存の職務経歴書と自己PRを準備
        Resume resume = buildResumeWithSelfPromotions(USER_ID);
        List<SelfPromotion> originalSelfPromotions = resume.getSelfPromotions();
        SelfPromotion originalSelfPromotion1 = originalSelfPromotions.get(0);
        UUID originalSelfPromotion2Id = originalSelfPromotions.get(1).getId();

        // リクエスト準備
        // 1件目: 既存自己PR1を更新
        SelfPromotionRequest updateRequest = new SelfPromotionRequest(
                originalSelfPromotion1.getId(),
                "更新後自己PRタイトル",
                "更新後自己PRコンテンツ");

        // 2件目: 新規自己PR追加（IDはnull）
        SelfPromotionRequest addRequest = new SelfPromotionRequest(
                null,
                "新規自己PRタイトル",
                "新規自己PRコンテンツ");

        UpdateSelfPromotionsRequest request = new UpdateSelfPromotionsRequest(List.of(updateRequest, addRequest));

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

        // 自己PR件数: 既存1件更新＋新規1件追加、もう1件は削除されて合計2件
        assertThat(saved.getSelfPromotions()).hasSize(2);

        // 既存自己PR1が更新されていることを検証
        SelfPromotion updatedSelfPromotion1 = saved.getSelfPromotions().stream()
                .filter(s -> s.getId().equals(originalSelfPromotion1.getId()))
                .findFirst()
                .orElseThrow();
        assertThat(updatedSelfPromotion1.getTitle()).isEqualTo("更新後自己PRタイトル");
        assertThat(updatedSelfPromotion1.getContent()).isEqualTo("更新後自己PRコンテンツ");

        // 新規追加された自己PRが存在することを検証（タイトルで判定）
        SelfPromotion addedSelfPromotion = saved.getSelfPromotions().stream()
                .filter(s -> "新規自己PRタイトル".equals(s.getTitle()))
                .findFirst()
                .orElseThrow();
        assertThat(addedSelfPromotion.getContent()).isEqualTo("新規自己PRコンテンツ");

        // 削除対象だった既存自己PR2が存在しないことを検証
        assertThat(saved.getSelfPromotions().stream()
                .noneMatch(s -> s.getId().equals(originalSelfPromotion2Id))).isTrue();

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
        UpdateSelfPromotionsRequest request = new UpdateSelfPromotionsRequest(List.of());

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
    @DisplayName("ログインユーザー以外が所有する職務経歴書の自己PRを更新しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // リクエスト準備
        SelfPromotionRequest requestSelfPromotion = new SelfPromotionRequest(
                null,
                "ダミー自己PRタイトル",
                "ダミー自己PRコンテンツ");
        UpdateSelfPromotionsRequest request = new UpdateSelfPromotionsRequest(List.of(requestSelfPromotion));

        // 職務経歴書（所有者は別ユーザー）を準備
        Resume resume = buildResumeWithSelfPromotions(OTHER_USER_ID);

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
    @DisplayName("更新対象の自己PRが存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // リクエスト準備（存在しないIDを指定）
        SelfPromotionRequest requestSelfPromotion = new SelfPromotionRequest(
                UUID.fromString("99999999-9999-9999-9999-999999999999"),
                "存在しない自己PRタイトル",
                "存在しない自己PRコンテンツ");
        UpdateSelfPromotionsRequest request = new UpdateSelfPromotionsRequest(List.of(requestSelfPromotion));

        // 既存の職務経歴書と自己PRを準備
        Resume resume = buildResumeWithSelfPromotions(USER_ID);

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("更新対象の自己PR情報が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("空配列が送信された場合、既存の自己PRがすべて削除される")
    void test5() {
        // 既存の職務経歴書と自己PRを準備（自己PR2件）
        Resume resume = buildResumeWithSelfPromotions(USER_ID);
        assertThat(resume.getSelfPromotions()).hasSize(2);

        // リクエスト準備（空配列）
        UpdateSelfPromotionsRequest request = new UpdateSelfPromotionsRequest(List.of());

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        useCase.execute(USER_ID, RESUME_ID, request);

        // save() に渡された Resume をキャプチャ
        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        // すべて削除されていることを検証
        assertThat(saved.getSelfPromotions()).isEmpty();
    }

    @Test
    @DisplayName("自己PRリストがnullの場合、NullPointerExceptionがスローされる")
    void test6() {
        // 既存の職務経歴書を準備
        Resume resume = buildResumeWithSelfPromotions(USER_ID);

        // リクエスト準備（自己PRリストがnull）
        UpdateSelfPromotionsRequest request = new UpdateSelfPromotionsRequest(null);

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
     * 自己PR2件を持つ職務経歴書を作成するヘルパーメソッド
     */
    private Resume buildResumeWithSelfPromotions(UUID ownerId) {
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

        // 自己PR1
        SelfPromotion selfPromotion1 = SelfPromotion.create(
                notification,
                "自己PR1タイトル",
                "自己PR1コンテンツ");
        Resume resumeWithSelfPromotion1 = base.addSelfPromotion(notification, selfPromotion1);

        // 自己PR2
        SelfPromotion selfPromotion2 = SelfPromotion.create(
                notification,
                "自己PR2タイトル",
                "自己PR2コンテンツ");

        return resumeWithSelfPromotion1.addSelfPromotion(notification, selfPromotion2);
    }
}
