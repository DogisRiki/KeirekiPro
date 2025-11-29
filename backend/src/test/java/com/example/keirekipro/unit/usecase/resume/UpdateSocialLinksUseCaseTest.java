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
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.model.resume.SocialLink;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateSocialLinksRequest;
import com.example.keirekipro.presentation.resume.dto.UpdateSocialLinksRequest.SocialLinkRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.UpdateSocialLinksUseCase;
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
class UpdateSocialLinksUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private UpdateSocialLinksUseCase useCase;

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
    @DisplayName("ソーシャルリンクを追加・更新・削除できる")
    void test1() {
        // 既存の職務経歴書とソーシャルリンクを準備
        Resume resume = buildResumeWithSocialLinks(USER_ID);
        List<SocialLink> originalSocialLinks = resume.getSocialLinks();
        SocialLink originalSocialLink1 = originalSocialLinks.get(0);
        UUID originalSocialLink2Id = originalSocialLinks.get(1).getId();

        // リクエスト準備
        // 1件目: 既存ソーシャルリンク1を更新
        SocialLinkRequest updateRequest = new SocialLinkRequest(
                originalSocialLink1.getId(),
                "更新後SNS",
                "https://example.com/updated-sns");

        // 2件目: 新規ソーシャルリンク追加（IDはnull）
        SocialLinkRequest addRequest = new SocialLinkRequest(
                null,
                "新規SNS",
                "https://example.com/new-sns");

        UpdateSocialLinksRequest request = new UpdateSocialLinksRequest(List.of(updateRequest, addRequest));

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

        // ソーシャルリンク件数: 既存1件更新＋新規1件追加、もう1件は削除されて合計2件
        assertThat(saved.getSocialLinks()).hasSize(2);

        // 既存ソーシャルリンク1が更新されていることを検証
        SocialLink updatedSocialLink1 = saved.getSocialLinks().stream()
                .filter(s -> s.getId().equals(originalSocialLink1.getId()))
                .findFirst()
                .orElseThrow();
        assertThat(updatedSocialLink1.getName()).isEqualTo("更新後SNS");
        assertThat(updatedSocialLink1.getLink().getValue()).isEqualTo("https://example.com/updated-sns");

        // 新規追加されたソーシャルリンクが存在することを検証（名前で判定）
        SocialLink addedSocialLink = saved.getSocialLinks().stream()
                .filter(s -> "新規SNS".equals(s.getName()))
                .findFirst()
                .orElseThrow();
        assertThat(addedSocialLink.getLink().getValue()).isEqualTo("https://example.com/new-sns");

        // 削除対象だった既存ソーシャルリンク2が存在しないことを検証
        assertThat(saved.getSocialLinks().stream()
                .noneMatch(s -> s.getId().equals(originalSocialLink2Id))).isTrue();

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
        UpdateSocialLinksRequest request = new UpdateSocialLinksRequest(List.of());

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
    @DisplayName("ログインユーザー以外が所有する職務経歴書のソーシャルリンクを更新しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // リクエスト準備
        SocialLinkRequest requestSocialLink = new SocialLinkRequest(
                null,
                "ダミーSNS",
                "https://example.com/dummy");
        UpdateSocialLinksRequest request = new UpdateSocialLinksRequest(List.of(requestSocialLink));

        // 職務経歴書（所有者は別ユーザー）を準備
        Resume resume = buildResumeWithSocialLinks(OTHER_USER_ID);

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
    @DisplayName("更新対象のソーシャルリンクが存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // リクエスト準備（存在しないIDを指定）
        SocialLinkRequest requestSocialLink = new SocialLinkRequest(
                UUID.fromString("99999999-9999-9999-9999-999999999999"),
                "存在しないSNS更新",
                "https://example.com/dummy");
        UpdateSocialLinksRequest request = new UpdateSocialLinksRequest(List.of(requestSocialLink));

        // 既存の職務経歴書とソーシャルリンクを準備
        Resume resume = buildResumeWithSocialLinks(USER_ID);

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("更新対象のSNS情報が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("空配列が送信された場合、既存のソーシャルリンクがすべて削除される")
    void test5() {
        // 既存の職務経歴書とソーシャルリンクを準備（ソーシャルリンク2件）
        Resume resume = buildResumeWithSocialLinks(USER_ID);
        assertThat(resume.getSocialLinks()).hasSize(2);

        // リクエスト準備（空配列）
        UpdateSocialLinksRequest request = new UpdateSocialLinksRequest(List.of());

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        useCase.execute(USER_ID, RESUME_ID, request);

        // save() に渡された Resume をキャプチャ
        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        // すべて削除されていることを検証
        assertThat(saved.getSocialLinks()).isEmpty();
    }

    @Test
    @DisplayName("ソーシャルリンクリストがnullの場合、NullPointerExceptionがスローされる")
    void test6() {
        // 既存の職務経歴書を準備
        Resume resume = buildResumeWithSocialLinks(USER_ID);

        // リクエスト準備（ソーシャルリンクリストがnull）
        UpdateSocialLinksRequest request = new UpdateSocialLinksRequest(null);

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
     * ソーシャルリンク2件を持つ職務経歴書を作成するヘルパーメソッド
     */
    private Resume buildResumeWithSocialLinks(UUID ownerId) {
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

        // ソーシャルリンク1
        Link link1 = Link.create(notification, "https://example.com/twitter");
        SocialLink socialLink1 = SocialLink.create(
                notification,
                "Twitter",
                link1);
        Resume resumeWithSocialLink1 = base.addSociealLink(notification, socialLink1);

        // ソーシャルリンク2
        Link link2 = Link.create(notification, "https://example.com/github");
        SocialLink socialLink2 = SocialLink.create(
                notification,
                "GitHub",
                link2);

        return resumeWithSocialLink1.addSociealLink(notification, socialLink2);
    }
}
