package com.example.keirekipro.unit.domain.service.resume;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeNameDuplicationCheckService;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ResumeNameDuplicationCheckServiceTest {

    @Mock
    private ResumeRepository repository;

    @Mock
    private Notification notification;

    @InjectMocks
    private ResumeNameDuplicationCheckService service;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    private static final UUID RESUME_ID_1 = UUID.fromString("223e4567-e89b-12d3-a456-426614174000");
    private static final UUID RESUME_ID_2 = UUID.fromString("323e4567-e89b-12d3-a456-426614174000");

    private static final String RESUME_NAME_1 = "職務経歴書名1";
    private static final String RESUME_NAME_2 = "職務経歴書名2";
    private static final String RESUME_NAME_3 = "職務経歴書名3";

    private static final String LAST_NAME = "山田";
    private static final String FIRST_NAME = "太郎";

    private static final LocalDate DATE = LocalDate.of(2024, 6, 1);
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2024, 6, 1, 10, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2024, 6, 1, 12, 0);

    @Test
    @DisplayName("メールアドレスがnullの場合、重複チェックが行われない")
    void test1() {
        // 職務経歴書名がnullの値オブジェクト
        ResumeName resumeName = null;

        // 重複チェックを実行
        assertThatCode(() -> service.execute(USER_ID, resumeName)).doesNotThrowAnyException();

        // 職務経歴書検索が呼ばれない
        verify(repository, never()).findAll(any());
    }

    @Test
    @DisplayName("同名の職務経歴書名が存在する場合、DomainExceptionをスローする")
    void test2() {
        // モックをセットアップ
        when(repository.findAll(USER_ID)).thenReturn(List.of(
                ResumeObjectBuilder.buildResume(RESUME_ID_1, USER_ID, RESUME_NAME_1, DATE, LAST_NAME, FIRST_NAME,
                        CREATED_AT, UPDATED_AT),
                ResumeObjectBuilder.buildResume(RESUME_ID_2, USER_ID, RESUME_NAME_2, DATE, LAST_NAME, FIRST_NAME,
                        CREATED_AT, UPDATED_AT)));

        // 重複する職務経歴書名
        ResumeName resumeName = ResumeName.create(notification, RESUME_NAME_1);

        // 重複チェックを実行
        assertThatThrownBy(() -> service.execute(USER_ID, resumeName))
                .isInstanceOf(DomainException.class)
                .hasMessage("この職務経歴書名は既に登録されています。");
    }

    @Test
    @DisplayName("同名の職務経歴書名が存在しない場合、DomainExceptionがスローされない")
    void test3() {
        // モックをセットアップ
        when(repository.findAll(USER_ID)).thenReturn(List.of(
                ResumeObjectBuilder.buildResume(RESUME_ID_1, USER_ID, RESUME_NAME_1, DATE, LAST_NAME, FIRST_NAME,
                        CREATED_AT, UPDATED_AT),
                ResumeObjectBuilder.buildResume(RESUME_ID_2, USER_ID, RESUME_NAME_2, DATE, LAST_NAME, FIRST_NAME,
                        CREATED_AT, UPDATED_AT)));

        // チェック対象の職務経歴書名
        ResumeName resumeName = ResumeName.create(notification, RESUME_NAME_3);

        // 重複チェックを実行
        assertThatCode(() -> service.execute(USER_ID, resumeName)).doesNotThrowAnyException();

        // 職務経歴書検索が呼ばれる
        verify(repository, times(1)).findAll(USER_ID);
    }
}
