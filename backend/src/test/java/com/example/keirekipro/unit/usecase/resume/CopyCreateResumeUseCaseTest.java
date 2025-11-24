package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeNameDuplicationCheckService;
import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.presentation.resume.dto.CreateResumeRequest;
import com.example.keirekipro.usecase.resume.CopyCreateResumeUseCase;
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
class CopyCreateResumeUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @Mock
    private ResumeNameDuplicationCheckService service;

    @InjectMocks
    private CopyCreateResumeUseCase useCase;

    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID OTHER_USER_ID = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final String ORIGINAL_NAME = "職務経歴書1";
    private static final String NEW_NAME = "職務経歴書New";
    private static final LocalDate DATE = LocalDate.of(2021, 5, 20);
    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2021, 5, 15, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2021, 5, 18, 15, 30);

    @Test
    @DisplayName("職務経歴書をコピーして新規作成ができる")
    void test1() {
        // リクエスト準備
        CreateResumeRequest request = new CreateResumeRequest(NEW_NAME, RESUME_ID);

        // コピー元エンティティをヘルパーで生成
        Resume source = ResumeObjectBuilder.buildResume(
                RESUME_ID, USER_ID, ORIGINAL_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        // モック
        doNothing().when(service).execute(eq(USER_ID), any(ResumeName.class));
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(source));

        // 実行
        ArgumentCaptor<Resume> captor = ArgumentCaptor.forClass(Resume.class);
        ResumeInfoUseCaseDto actual = useCase.execute(USER_ID, request);

        // 検証
        verify(service).execute(eq(USER_ID), any(ResumeName.class));
        verify(repository).find(RESUME_ID);
        verify(repository).save(captor.capture());

        // save()で受け取ったResumeからDTOを組み立て、それを比較
        Resume saved = captor.getValue();
        ResumeInfoUseCaseDto expected = ResumeInfoUseCaseDto.convertToUseCaseDto(saved);

        assertThat(actual)
                .usingRecursiveComparison()
                .isEqualTo(expected);
    }

    @Test
    @DisplayName("職務経歴書名が重複していた場合、例外がスローされ後続処理が行われない")
    void test2() {
        CreateResumeRequest request = new CreateResumeRequest(NEW_NAME, RESUME_ID);

        doThrow(new UseCaseException("この職務経歴書名は既に登録されています。"))
                .when(service).execute(eq(USER_ID), any(ResumeName.class));

        assertThatThrownBy(() -> useCase.execute(USER_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("この職務経歴書名は既に登録されています。");

        verify(service).execute(eq(USER_ID), any(ResumeName.class));
        verify(repository, never()).find(any());
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書をコピーしようとした場合、UseCaseExceptionがスローされる")
    void test3() {
        // リクエスト準備
        CreateResumeRequest request = new CreateResumeRequest(NEW_NAME, RESUME_ID);

        // コピー元エンティティ（所有者は別ユーザー）
        Resume source = ResumeObjectBuilder.buildResume(
                RESUME_ID, OTHER_USER_ID, ORIGINAL_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);

        // モック
        doNothing().when(service).execute(eq(USER_ID), any(ResumeName.class));
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(source));

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("コピー元の職務経歴書が存在しません。");

        verify(service).execute(eq(USER_ID), any(ResumeName.class));
        verify(repository).find(RESUME_ID);
        verify(repository, never()).save(any());
    }
}
