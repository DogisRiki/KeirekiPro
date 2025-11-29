package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.presentation.resume.dto.UpdateResumeBasicRequest;
import com.example.keirekipro.usecase.resume.UpdateResumeBasicUseCase;
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
class UpdateResumeBasicUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private UpdateResumeBasicUseCase useCase;

    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID OTHER_USER_ID = UUID.fromString("33333333-3333-3333-3333-333333333333");

    private static final String ORIGINAL_RESUME_NAME = "職務経歴書1";
    private static final String NEW_RESUME_NAME = "更新後職務経歴書";
    private static final LocalDate ORIGINAL_DATE = LocalDate.of(2021, 5, 20);
    private static final LocalDate NEW_DATE = LocalDate.of(2022, 1, 1);
    private static final String ORIGINAL_LAST_NAME = "山田";
    private static final String ORIGINAL_FIRST_NAME = "太郎";
    private static final String NEW_LAST_NAME = "佐藤";
    private static final String NEW_FIRST_NAME = "花子";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2021, 5, 15, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2021, 5, 18, 15, 30);

    @Test
    @DisplayName("職務経歴書の基本情報を更新できる")
    void test1() {
        // リクエスト準備
        UpdateResumeBasicRequest request = new UpdateResumeBasicRequest(
                NEW_RESUME_NAME,
                NEW_DATE,
                NEW_LAST_NAME,
                NEW_FIRST_NAME);

        // 既存エンティティをヘルパーで生成
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, USER_ID, ORIGINAL_RESUME_NAME, ORIGINAL_DATE,
                ORIGINAL_LAST_NAME, ORIGINAL_FIRST_NAME, CREATED_AT, UPDATED_AT);

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

        // 基本情報が更新されていることを検証
        ResumeName savedName = saved.getName();
        FullName savedFullName = saved.getFullName();

        assertThat(savedName.getValue()).isEqualTo(NEW_RESUME_NAME);
        assertThat(saved.getDate()).isEqualTo(NEW_DATE);
        assertThat(savedFullName.getLastName()).isEqualTo(NEW_LAST_NAME);
        assertThat(savedFullName.getFirstName()).isEqualTo(NEW_FIRST_NAME);

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
        UpdateResumeBasicRequest request = new UpdateResumeBasicRequest(
                NEW_RESUME_NAME,
                NEW_DATE,
                NEW_LAST_NAME,
                NEW_FIRST_NAME);

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
    @DisplayName("ログインユーザー以外が所有する職務経歴書の基本情報を更新しようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // リクエスト準備
        UpdateResumeBasicRequest request = new UpdateResumeBasicRequest(
                NEW_RESUME_NAME,
                NEW_DATE,
                NEW_LAST_NAME,
                NEW_FIRST_NAME);

        // 職務経歴書自体は存在するが、所有者が別ユーザー
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, OTHER_USER_ID, ORIGINAL_RESUME_NAME, ORIGINAL_DATE,
                ORIGINAL_LAST_NAME, ORIGINAL_FIRST_NAME, CREATED_AT, UPDATED_AT);

        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }
}
