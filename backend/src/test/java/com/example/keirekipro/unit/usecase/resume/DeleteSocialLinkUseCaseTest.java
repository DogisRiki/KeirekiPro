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
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.DeleteSocialLinkUseCase;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class DeleteSocialLinkUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private DeleteSocialLinkUseCase useCase;

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
    @DisplayName("SNSを削除できる")
    void test1() {
        Resume resume = buildResumeWithSocialLinks(USER_ID);
        UUID socialLinkId = resume.getSocialLinks().get(0).getId();

        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        useCase.execute(USER_ID, RESUME_ID, socialLinkId);

        verify(repository).find(RESUME_ID);

        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        assertThat(saved.getSocialLinks()).hasSize(1);
        assertThat(saved.getSocialLinks().stream().anyMatch(s -> s.getId().equals(socialLinkId))).isFalse();
    }

    @Test
    @DisplayName("対象の職務経歴書が存在しない場合、UseCaseExceptionがスローされる")
    void test2() {
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        UUID socialLinkId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, socialLinkId))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書のSNSを削除しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        Resume resume = buildResumeWithSocialLinks(OTHER_USER_ID);
        UUID socialLinkId = resume.getSocialLinks().get(0).getId();

        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, socialLinkId))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("削除対象のSNSが存在しない場合、UseCaseExceptionがスローされる")
    void test4() {
        Resume resume = buildResumeWithSocialLinks(USER_ID);

        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        UUID missingId = UUID.fromString("99999999-9999-9999-9999-999999999999");
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, missingId))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("対象のSNSが存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    private Resume buildResumeWithSocialLinks(UUID ownerId) {
        Notification notification = new Notification();

        ResumeName resumeName = ResumeName.create(notification, RESUME_NAME);
        FullName fullName = FullName.create(notification, LAST_NAME, FIRST_NAME);

        Link link1 = Link.create(notification, "https://github.com/example");
        SocialLink s1 = SocialLink.create(notification, "GitHub", link1);

        Link link2 = Link.create(notification, "https://x.com/example");
        SocialLink s2 = SocialLink.create(notification, "X", link2);

        return Resume.reconstruct(
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
                List.of(s1, s2), // socialLinks
                List.of() // selfPromotions
        );
    }
}
