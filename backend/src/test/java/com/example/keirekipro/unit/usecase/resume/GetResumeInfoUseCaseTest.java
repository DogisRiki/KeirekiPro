package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.usecase.resume.GetResumeInfoUseCase;
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
class GetResumeInfoUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private GetResumeInfoUseCase useCase;

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
    @DisplayName("職務経歴書情報を取得できる")
    void test1() {
        // モック準備
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行
        ResumeInfoUseCaseDto actual = useCase.execute(USER_ID, RESUME_ID);

        // 期待値DTOは同一Resumeから変換する（IDの不一致を防止）
        var expected = ResumeInfoUseCaseDto.convertToUseCaseDto(resume);

        // repository.findに渡された引数をキャプチャして検証
        var captor = ArgumentCaptor.forClass(UUID.class);
        verify(repository).find(captor.capture());
        assertThat(captor.getValue()).isEqualTo(RESUME_ID);

        // DTOのフィールドを再帰比較で検証
        assertThat(actual)
                .usingRecursiveComparison()
                .isEqualTo(expected);
    }

    @Test
    @DisplayName("対象の職務経歴書情報が存在しない場合、UseCaseExceptionがスローされる")
    void test2() {
        // モック準備
        when(repository.find(RESUME_ID)).thenReturn(Optional.empty());

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
    }

    @Test
    @DisplayName("ログインユーザー以外が所有する職務経歴書IDを指定した場合、UseCaseExceptionがスローされる")
    void test3() {
        // モック準備（職務経歴書自体は存在するが、所有者が別ユーザー）
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, OTHER_USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);
        when(repository.find(RESUME_ID)).thenReturn(Optional.of(resume));

        // 実行＆検証
        assertThatThrownBy(() -> useCase.execute(USER_ID, RESUME_ID))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("職務経歴書が存在しません。");

        verify(repository).find(RESUME_ID);
    }
}
