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
import com.example.keirekipro.presentation.resume.dto.UpdateSelfPromotionRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.UpdateSelfPromotionUseCase;
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
class UpdateSelfPromotionUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private UpdateSelfPromotionUseCase useCase;

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
    @DisplayName("自己PRを更新できる")
    void test1() {
        // 既存の職務経歴書と自己PRを準備
        Resume resume = buildResumeWithSelfPromotions(USER_ID);

        // リクエスト準備
        UpdateSelfPromotionRequest request = new UpdateSelfPromotionRequest(
                "更新後自己PRタイトル",
                "更新後自己PRコンテンツ");

        // 更新対象IDは、並び順に依存しないようタイトルで特定する
        UUID selfPromotionId = resume.getSelfPromotions().stream()
                .filter(sp -> "自己PR1タイトル".equals(sp.getTitle()))
                .map(SelfPromotion::getId)
                .findFirst()
                .orElseThrow();

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        ResumeInfoUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID, selfPromotionId, request);

        // repository.find に渡された引数を検証
        ArgumentCaptor<UUID> findCaptor = ArgumentCaptor.forClass(UUID.class);
        verify(repository).find(findCaptor.capture());
        assertThat(findCaptor.getValue()).isEqualTo(RESUME_ID);

        // save() に渡された Resume をキャプチャ
        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        // 件数は変わらない（更新のみ）
        assertThat(saved.getSelfPromotions()).hasSize(2);

        // 更新対象が更新されていることを検証
        SelfPromotion updated = saved.getSelfPromotions().stream()
                .filter(sp -> sp.getId().equals(selfPromotionId))
                .findFirst()
                .orElseThrow();

        assertThat(updated.getTitle()).isEqualTo("更新後自己PRタイトル");
        assertThat(updated.getContent()).isEqualTo("更新後自己PRコンテンツ");

        // 他の自己PRが保持されていることを検証（自己PR2）
        assertThat(saved.getSelfPromotions().stream()
                .anyMatch(sp -> "自己PR2タイトル".equals(sp.getTitle()))).isTrue();

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
        UpdateSelfPromotionRequest request = new UpdateSelfPromotionRequest(
                "更新後自己PRタイトル",
                "更新後自己PRコンテンツ");

        // モック準備（対象の職務経歴書が存在しない）
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        // 実行＆検証
        UUID selfPromotionId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, selfPromotionId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書の自己PRを更新しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // 職務経歴書（所有者は別ユーザー）を準備
        Resume resume = buildResumeWithSelfPromotions(OTHER_USER_ID);

        // リクエスト準備
        UpdateSelfPromotionRequest request = new UpdateSelfPromotionRequest(
                "更新後自己PRタイトル",
                "更新後自己PRコンテンツ");

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        UUID selfPromotionId = resume.getSelfPromotions().stream()
                .map(SelfPromotion::getId)
                .findFirst()
                .orElseThrow();

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, selfPromotionId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("更新対象の自己PRが存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // 既存の職務経歴書を準備
        Resume resume = buildResumeWithSelfPromotions(USER_ID);

        // リクエスト準備
        UpdateSelfPromotionRequest request = new UpdateSelfPromotionRequest(
                "存在しない自己PRタイトル",
                "存在しない自己PRコンテンツ");

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        UUID missingSelfPromotionId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, missingSelfPromotionId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("対象の自己PRが存在しません。");

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
                List.of(), // snsPlatforms
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
