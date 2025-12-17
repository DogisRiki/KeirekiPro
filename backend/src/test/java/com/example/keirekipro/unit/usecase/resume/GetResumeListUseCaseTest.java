package com.example.keirekipro.unit.usecase.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.usecase.resume.GetResumeListUseCase;
import com.example.keirekipro.usecase.resume.dto.ResumeListUseCaseDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class GetResumeListUseCaseTest {

    @Mock
    private ResumeRepository repository;

    @InjectMocks
    private GetResumeListUseCase useCase;

    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID1 = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID RESUME_ID2 = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final String RESUME_NAME1 = "職務経歴書1";
    private static final String RESUME_NAME2 = "職務経歴書2";
    private static final LocalDate DATE = LocalDate.of(2021, 5, 20);
    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2021, 5, 15, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2021, 5, 18, 15, 30);

    @Test
    @DisplayName("職務経歴書一覧を取得できる")
    void test1() {
        // モック設定
        Resume r1 = ResumeObjectBuilder.buildResume(
                RESUME_ID1, USER_ID, RESUME_NAME1, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);
        Resume r2 = ResumeObjectBuilder.buildResume(
                RESUME_ID2, USER_ID, RESUME_NAME2, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);
        when(repository.findAll(USER_ID)).thenReturn(List.of(r1, r2));

        // 実行
        List<ResumeListUseCaseDto> actual = useCase.execute(USER_ID);

        // 検証
        assertThat(actual).hasSize(2);
        assertThat(actual.get(0).getId()).isEqualTo(RESUME_ID1);
        assertThat(actual.get(0).getResumeName()).isEqualTo(RESUME_NAME1);
        assertThat(actual.get(0).getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(actual.get(0).getUpdatedAt()).isEqualTo(UPDATED_AT);
        assertThat(actual.get(1).getId()).isEqualTo(RESUME_ID2);
        assertThat(actual.get(1).getResumeName()).isEqualTo(RESUME_NAME2);
        assertThat(actual.get(1).getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(actual.get(1).getUpdatedAt()).isEqualTo(UPDATED_AT);
        verify(repository).findAll(USER_ID);
    }

    @Test
    @DisplayName("職務経歴書が１つもない場合、空のリストが返る")
    void test2() {
        // モック設定
        when(repository.findAll(USER_ID)).thenReturn(List.of());

        // 実行
        List<ResumeListUseCaseDto> actual = useCase.execute(USER_ID);

        // 検証
        assertThat(actual).isEmpty();
        verify(repository).findAll(USER_ID);
    }
}
