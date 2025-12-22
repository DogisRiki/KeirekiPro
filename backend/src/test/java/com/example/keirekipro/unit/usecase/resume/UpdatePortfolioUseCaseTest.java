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
import com.example.keirekipro.presentation.resume.dto.UpdatePortfolioRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.UpdatePortfolioUseCase;
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
class UpdatePortfolioUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private UpdatePortfolioUseCase useCase;

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
    @DisplayName("ポートフォリオを更新できる")
    void test1() {
        // 既存の職務経歴書とポートフォリオを準備
        Resume resume = buildResumeWithPortfolios(USER_ID);

        // リクエスト準備
        UpdatePortfolioRequest request = new UpdatePortfolioRequest(
                "更新後ポートフォリオ",
                "更新後概要",
                "更新後技術スタック",
                "https://example.com/updated");

        // 更新対象IDは、並び順に依存しないよう名前で特定する
        UUID portfolioId = resume.getPortfolios().stream()
                .filter(p -> "ポートフォリオ1".equals(p.getName()))
                .map(Portfolio::getId)
                .findFirst()
                .orElseThrow();

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        ResumeInfoUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID, portfolioId, request);

        // repository.find に渡された引数を検証
        ArgumentCaptor<UUID> findCaptor = ArgumentCaptor.forClass(UUID.class);
        verify(repository).find(findCaptor.capture());
        assertThat(findCaptor.getValue()).isEqualTo(RESUME_ID);

        // save() に渡された Resume をキャプチャ
        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        // 件数は変わらない（更新のみ）
        assertThat(saved.getPortfolios()).hasSize(2);

        // 更新対象が更新されていることを検証
        Portfolio updated = saved.getPortfolios().stream()
                .filter(p -> p.getId().equals(portfolioId))
                .findFirst()
                .orElseThrow();

        assertThat(updated.getName()).isEqualTo("更新後ポートフォリオ");
        assertThat(updated.getOverview()).isEqualTo("更新後概要");
        assertThat(updated.getTechStack()).isEqualTo("更新後技術スタック");
        assertThat(updated.getLink().getValue()).isEqualTo("https://example.com/updated");

        // 他のポートフォリオが保持されていることを検証（ポートフォリオ2）
        assertThat(saved.getPortfolios().stream()
                .anyMatch(p -> "ポートフォリオ2".equals(p.getName()))).isTrue();

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
        UpdatePortfolioRequest request = new UpdatePortfolioRequest(
                "更新後ポートフォリオ",
                "更新後概要",
                "更新後技術スタック",
                "https://example.com/updated");

        // モック準備（対象の職務経歴書が存在しない）
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        // 実行＆検証
        UUID portfolioId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, portfolioId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書のポートフォリオを更新しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // 職務経歴書（所有者は別ユーザー）を準備
        Resume resume = buildResumeWithPortfolios(OTHER_USER_ID);

        // リクエスト準備
        UpdatePortfolioRequest request = new UpdatePortfolioRequest(
                "更新後ポートフォリオ",
                "更新後概要",
                "更新後技術スタック",
                "https://example.com/updated");

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        UUID portfolioId = resume.getPortfolios().stream()
                .map(Portfolio::getId)
                .findFirst()
                .orElseThrow();

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, portfolioId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("更新対象のポートフォリオが存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // 既存の職務経歴書を準備
        Resume resume = buildResumeWithPortfolios(USER_ID);

        // リクエスト準備
        UpdatePortfolioRequest request = new UpdatePortfolioRequest(
                "存在しないポートフォリオ更新",
                "ダミー概要",
                "ダミー技術スタック",
                "https://example.com/dummy");

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        UUID missingPortfolioId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, missingPortfolioId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("対象のポートフォリオが存在しません。");

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
                List.of(), // snsPlatforms
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
