package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import java.time.LocalDate;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeNameDuplicationCheckService;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.presentation.resume.dto.CreateResumeRequest;
import com.example.keirekipro.usecase.resume.CreateResumeUseCase;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.resume.policy.ResumeLimitChecker;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class CreateResumeUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @Mock
    private ResumeNameDuplicationCheckService service;

    @Mock
    private ResumeLimitChecker checker;

    @InjectMocks
    private CreateResumeUseCase useCase;

    private static final String RESUME_NAME = "職務経歴書1";

    @Test
    @DisplayName("職務経歴書の新規作成ができる")
    void test1() {
        // データ準備
        UUID userId = UUID.randomUUID();
        CreateResumeRequest request = new CreateResumeRequest(RESUME_NAME, null);

        // モックをセットアップ：重複チェックは何も起こさない
        doNothing().when(service).execute(eq(userId), any(ResumeName.class));
        // モックをセットアップ：上限チェックは何も起こさない
        doNothing().when(checker).checkResumeCreateAllowed(userId);

        // ユースケース実行
        assertThatCode(() -> useCase.execute(userId, request)).doesNotThrowAnyException();

        // 重複チェックが呼び出される
        verify(service).execute(eq(userId), any(ResumeName.class));
        // 上限チェックが呼び出される
        verify(checker).checkResumeCreateAllowed(userId);

        // repository.saveが呼ばれ、適切なResumeオブジェクトが渡される
        ArgumentCaptor<Resume> captor = ArgumentCaptor.forClass(Resume.class);
        verify(repository).save(captor.capture());
        Resume saved = captor.getValue();
        assertThat(saved.getName().getValue()).isEqualTo(RESUME_NAME);
        assertThat(saved.getUserId()).isEqualTo(userId);
        assertThat(saved.getDate()).isEqualTo(LocalDate.now());

        // 戻り値のDTOの内容を検証
        ResumeInfoUseCaseDto dto = useCase.execute(userId, request);
        assertThat(dto.getResumeName()).isEqualTo(RESUME_NAME);
        assertThat(dto.getDate()).isNotNull();
        assertThat(dto.getCreatedAt()).isNotNull();
        assertThat(dto.getUpdatedAt()).isNotNull();
        assertThat(dto.getLastName()).isNull();
        assertThat(dto.getFirstName()).isNull();
        assertThat(dto.getCareers()).isEmpty();
        assertThat(dto.getProjects()).isEmpty();
    }

    @Test
    @DisplayName("職務経歴書名が重複していた場合、例外がスローされ後続処理が行われない")
    void test2() {
        // データ準備
        UUID userId = UUID.randomUUID();
        CreateResumeRequest request = new CreateResumeRequest("重複職務経歴書", null);

        // モックをセットアップ：重複チェックでDomainExceptionを投げる
        doThrow(new DomainException("この職務経歴書名は既に登録されています。"))
                .when(service).execute(eq(userId), any(ResumeName.class));

        // ユースケース実行＆DomainExceptionがスローされることを検証
        assertThatThrownBy(() -> useCase.execute(userId, request))
                .isInstanceOf(DomainException.class)
                .hasMessage("この職務経歴書名は既に登録されています。");

        // 重複チェックは呼ばれるが、後続処理は行われない
        verify(service).execute(eq(userId), any(ResumeName.class));
        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("職務経歴書が上限枚数である場合、例外がスローされ後続処理が行われない")
    void test3() {
        // データ準備
        UUID userId = UUID.randomUUID();
        CreateResumeRequest request = new CreateResumeRequest("上限超職務経歴書", null);

        // モックをセットアップ：上限チェックでUseCaseExceptionを投げる
        doThrow(new UseCaseException("上限")).when(checker).checkResumeCreateAllowed(userId);

        // ユースケース実行＆UseCaseExceptionがスローされることを検証
        assertThatThrownBy(() -> useCase.execute(userId, request))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("上限");

        // 上限チェックは呼ばれるが、後続処理は行われない
        verify(checker).checkResumeCreateAllowed(userId);
        verify(service, never()).execute(any(), any());
        verify(repository, never()).save(any());
    }
}
