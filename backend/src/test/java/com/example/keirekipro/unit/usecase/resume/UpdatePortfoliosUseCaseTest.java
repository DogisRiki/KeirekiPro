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
import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdatePortfoliosRequest;
import com.example.keirekipro.presentation.resume.dto.UpdatePortfoliosRequest.PortfolioRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.UpdatePortfoliosUseCase;
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
class UpdatePortfoliosUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private UpdatePortfoliosUseCase useCase;

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
    @DisplayName("ポートフォリオを追加・更新・削除できる")
    void test1() {
        // 既存の職務経歴書とポートフォリオを準備
        Resume resume = buildResumeWithPortfolios(USER_ID);

        // getPortfolios() は並び替え済みのコピーを返すため、固定名に依存せず既存1件を特定する
        Portfolio originalPortfolio1 = resume.getPortfolios().stream()
                .findFirst()
                .orElseThrow();

        // リクエスト準備
        // 1件目: 既存ポートフォリオ1を更新
        PortfolioRequest updateRequest = new PortfolioRequest(
                originalPortfolio1.getId(),
                "更新後ポートフォリオ",
                "更新後概要",
                "更新後技術スタック",
                "https://example.com/updated");

        // 2件目: 新規ポートフォリオ追加（IDはnull）
        PortfolioRequest addRequest = new PortfolioRequest(
                null,
                "新規ポートフォリオ",
                "新規ポートフォリオ概要",
                "新規技術スタック",
                "https://example.com/new");

        UpdatePortfoliosRequest request = new UpdatePortfoliosRequest(List.of(updateRequest, addRequest));

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

        // ポートフォリオ件数: 既存1件更新＋新規1件追加、もう1件は削除されて合計2件
        assertThat(saved.getPortfolios()).hasSize(2);

        // 既存ポートフォリオ1が更新されていることを検証
        Portfolio updatedPortfolio1 = saved.getPortfolios().stream()
                .filter(p -> p.getId().equals(originalPortfolio1.getId()))
                .findFirst()
                .orElseThrow();
        assertThat(updatedPortfolio1.getName()).isEqualTo("更新後ポートフォリオ");
        assertThat(updatedPortfolio1.getOverview()).isEqualTo("更新後概要");
        assertThat(updatedPortfolio1.getTechStack()).isEqualTo("更新後技術スタック");
        assertThat(updatedPortfolio1.getLink().getValue()).isEqualTo("https://example.com/updated");

        // 新規追加されたポートフォリオが存在することを検証（名前で判定）
        Portfolio addedPortfolio = saved.getPortfolios().stream()
                .filter(p -> "新規ポートフォリオ".equals(p.getName()))
                .findFirst()
                .orElseThrow();
        assertThat(addedPortfolio.getOverview()).isEqualTo("新規ポートフォリオ概要");
        assertThat(addedPortfolio.getTechStack()).isEqualTo("新規技術スタック");
        assertThat(addedPortfolio.getLink().getValue()).isEqualTo("https://example.com/new");

        // 削除対象だった既存ポートフォリオ（更新対象以外）が存在しないことを検証
        UUID originalPortfolio2Id = resume.getPortfolios().stream()
                .map(Portfolio::getId)
                .filter(id -> !id.equals(originalPortfolio1.getId()))
                .findFirst()
                .orElseThrow();
        assertThat(saved.getPortfolios().stream()
                .noneMatch(p -> p.getId().equals(originalPortfolio2Id))).isTrue();

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
        UpdatePortfoliosRequest request = new UpdatePortfoliosRequest(List.of());

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
    @DisplayName("ログインユーザー以外が所有する職務経歴書のポートフォリオを更新しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // リクエスト準備
        PortfolioRequest requestPortfolio = new PortfolioRequest(
                null,
                "ダミーポートフォリオ",
                "ダミー概要",
                "ダミー技術スタック",
                "https://example.com/dummy");
        UpdatePortfoliosRequest request = new UpdatePortfoliosRequest(List.of(requestPortfolio));

        // 職務経歴書（所有者は別ユーザー）を準備
        Resume resume = buildResumeWithPortfolios(OTHER_USER_ID);

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
    @DisplayName("更新対象のポートフォリオが存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // リクエスト準備（存在しないIDを指定）
        PortfolioRequest requestPortfolio = new PortfolioRequest(
                UUID.fromString("99999999-9999-9999-9999-999999999999"),
                "存在しないポートフォリオ更新",
                "ダミー概要",
                "ダミー技術スタック",
                "https://example.com/dummy");
        UpdatePortfoliosRequest request = new UpdatePortfoliosRequest(List.of(requestPortfolio));

        // 既存の職務経歴書とポートフォリオを準備
        Resume resume = buildResumeWithPortfolios(USER_ID);

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("更新対象のポートフォリオ情報が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("空配列が送信された場合、既存のポートフォリオがすべて削除される")
    void test5() {
        // 既存の職務経歴書とポートフォリオを準備（ポートフォリオ2件）
        Resume resume = buildResumeWithPortfolios(USER_ID);
        assertThat(resume.getPortfolios()).hasSize(2);

        // リクエスト準備（空配列）
        UpdatePortfoliosRequest request = new UpdatePortfoliosRequest(List.of());

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        useCase.execute(USER_ID, RESUME_ID, request);

        // save() に渡された Resume をキャプチャ
        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        // すべて削除されていることを検証
        assertThat(saved.getPortfolios()).isEmpty();
    }

    @Test
    @DisplayName("ポートフォリオリストがnullの場合、NullPointerExceptionがスローされる")
    void test6() {
        // 既存の職務経歴書を準備
        Resume resume = buildResumeWithPortfolios(USER_ID);

        // リクエスト準備（ポートフォリオリストがnull）
        UpdatePortfoliosRequest request = new UpdatePortfoliosRequest(null);

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証（ヌルポが発生することを明示的に確認）
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(NullPointerException.class);

        // findは呼ばれるが、saveは呼ばれないことを検証
        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    /**
     * ポートフォリオ2件を持つ職務経歴書を作成するヘルパーメソッド
     */
    private Resume buildResumeWithPortfolios(UUID ownerId) {
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

        // ポートフォリオ1
        Link link1 = Link.create(notification, "https://example.com/portfolio1");
        Portfolio portfolio1 = Portfolio.create(
                notification,
                "ポートフォリオ1",
                "概要1",
                "技術スタック1",
                link1);
        Resume resumeWithPortfolio1 = base.addPortfolio(notification, portfolio1);

        // ポートフォリオ2
        Link link2 = Link.create(notification, "https://example.com/portfolio2");
        Portfolio portfolio2 = Portfolio.create(
                notification,
                "ポートフォリオ2",
                "概要2",
                "技術スタック2",
                link2);

        return resumeWithPortfolio1.addPortfolio(notification, portfolio2);
    }
}
