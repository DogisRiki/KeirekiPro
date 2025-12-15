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
import com.example.keirekipro.presentation.resume.dto.UpdateSocialLinkRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.UpdateSocialLinkUseCase;
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
class UpdateSocialLinkUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private UpdateSocialLinkUseCase useCase;

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
    @DisplayName("SNSを更新できる")
    void test1() {
        // 既存の職務経歴書とSNSを準備
        Resume resume = buildResumeWithSocialLinks(USER_ID);

        // リクエスト準備
        UpdateSocialLinkRequest request = new UpdateSocialLinkRequest(
                "更新後SNS",
                "https://example.com/updated-sns");

        // 更新対象IDは、並び順に依存しないよう名前で特定する
        UUID socialLinkId = resume.getSocialLinks().stream()
                .filter(sl -> "Twitter".equals(sl.getName()))
                .map(SocialLink::getId)
                .findFirst()
                .orElseThrow();

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        ResumeInfoUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID, socialLinkId, request);

        // repository.find に渡された引数を検証
        ArgumentCaptor<UUID> findCaptor = ArgumentCaptor.forClass(UUID.class);
        verify(repository).find(findCaptor.capture());
        assertThat(findCaptor.getValue()).isEqualTo(RESUME_ID);

        // save() に渡された Resume をキャプチャ
        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        // 件数は変わらない（更新のみ）
        assertThat(saved.getSocialLinks()).hasSize(2);

        // 更新対象が更新されていることを検証
        SocialLink updated = saved.getSocialLinks().stream()
                .filter(sl -> sl.getId().equals(socialLinkId))
                .findFirst()
                .orElseThrow();

        assertThat(updated.getName()).isEqualTo("更新後SNS");
        assertThat(updated.getLink().getValue()).isEqualTo("https://example.com/updated-sns");

        // 他のSNSが保持されていることを検証（GitHub）
        assertThat(saved.getSocialLinks().stream()
                .anyMatch(sl -> "GitHub".equals(sl.getName()))).isTrue();

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
        UpdateSocialLinkRequest request = new UpdateSocialLinkRequest(
                "更新後SNS",
                "https://example.com/updated-sns");

        // モック準備（対象の職務経歴書が存在しない）
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        // 実行＆検証
        UUID socialLinkId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, socialLinkId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書のSNSを更新しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // 職務経歴書（所有者は別ユーザー）を準備
        Resume resume = buildResumeWithSocialLinks(OTHER_USER_ID);

        // リクエスト準備
        UpdateSocialLinkRequest request = new UpdateSocialLinkRequest(
                "更新後SNS",
                "https://example.com/updated-sns");

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        UUID socialLinkId = resume.getSocialLinks().stream()
                .map(SocialLink::getId)
                .findFirst()
                .orElseThrow();

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, socialLinkId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("更新対象のSNSが存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        // 既存の職務経歴書を準備
        Resume resume = buildResumeWithSocialLinks(USER_ID);

        // リクエスト準備
        UpdateSocialLinkRequest request = new UpdateSocialLinkRequest(
                "存在しないSNS更新",
                "https://example.com/dummy");

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        UUID missingSocialLinkId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, missingSocialLinkId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("対象のSNSが存在しません。");

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

        // SNS1
        Link link1 = Link.create(notification, "https://example.com/twitter");
        SocialLink socialLink1 = SocialLink.create(
                notification,
                "Twitter",
                link1);
        Resume resumeWithSocialLink1 = base.addSociealLink(notification, socialLink1);

        // SNS2
        Link link2 = Link.create(notification, "https://example.com/github");
        SocialLink socialLink2 = SocialLink.create(
                notification,
                "GitHub",
                link2);

        return resumeWithSocialLink1.addSociealLink(notification, socialLink2);
    }
}
