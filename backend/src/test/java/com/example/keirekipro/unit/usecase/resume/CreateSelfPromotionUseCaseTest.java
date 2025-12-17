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
import com.example.keirekipro.presentation.resume.dto.CreateSelfPromotionRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.CreateSelfPromotionUseCase;
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
class CreateSelfPromotionUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private CreateSelfPromotionUseCase useCase;

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
    @DisplayName("自己PRを新規作成できる")
    void test1() {
        CreateSelfPromotionRequest request = new CreateSelfPromotionRequest();
        request.setTitle("自己PRタイトル");
        request.setContent("自己PR本文");

        when(repository.find(RESUME_ID)).thenReturn(Optional.of(buildResume(USER_ID)));

        ResumeInfoUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID, request);

        verify(repository).find(RESUME_ID);

        ArgumentCaptor<Resume> saveCaptor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(saveCaptor.capture());
        Resume saved = saveCaptor.getValue();

        assertThat(saved.getSelfPromotions()).hasSize(1);
        SelfPromotion created = saved.getSelfPromotions().get(0);
        assertThat(created.getTitle()).isEqualTo("自己PRタイトル");
        assertThat(created.getContent()).isEqualTo("自己PR本文");

        ResumeInfoUseCaseDto expected = ResumeInfoUseCaseDto.convertToUseCaseDto(saved);
        assertThat(actual).usingRecursiveComparison().isEqualTo(expected);
    }

    @Test
    @DisplayName("対象の職務経歴書が存在しない場合、UseCaseExceptionがスローされる")
    void test2() {
        CreateSelfPromotionRequest request = new CreateSelfPromotionRequest();
        request.setTitle("自己PRタイトル");
        request.setContent("自己PR本文");

        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書に自己PRを作成しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        CreateSelfPromotionRequest request = new CreateSelfPromotionRequest();
        request.setTitle("自己PRタイトル");
        request.setContent("自己PR本文");

        when(repository.find(RESUME_ID)).thenReturn(Optional.of(buildResume(OTHER_USER_ID)));

        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }

    private Resume buildResume(UUID ownerId) {
        Notification notification = new Notification();

        ResumeName resumeName = ResumeName.create(notification, RESUME_NAME);
        FullName fullName = FullName.create(notification, LAST_NAME, FIRST_NAME);

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
                List.of(), // socialLinks
                List.of() // selfPromotions
        );
    }
}
