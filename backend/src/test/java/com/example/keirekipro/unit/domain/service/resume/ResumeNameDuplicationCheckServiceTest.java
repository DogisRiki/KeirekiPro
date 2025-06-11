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

import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeNameDuplicationCheckService;
import com.example.keirekipro.domain.shared.exception.DomainException;
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

    private static final UUID USERID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    @Test
    @DisplayName("メールアドレスがnullの場合、重複チェックが行われない")
    void test1() {
        // 職務経歴書名がnullの値オブジェクト
        ResumeName resumeName = null;

        // 重複チェックを実行
        assertThatCode(() -> service.execute(USERID, resumeName)).doesNotThrowAnyException();

        // 職務経歴書検索が呼ばれない
        verify(repository, never()).findAll(any());
    }

    @Test
    @DisplayName("同名の職務経歴書名が存在する場合、DomainExceptionをスローする")
    void test2() {
        // モックをセットアップ
        when(repository.findAll(USERID)).thenReturn(List.of(
                createSampleResume(UUID.fromString("223e4567-e89b-12d3-a456-426614174000"), USERID, "職務経歴書名1"),
                createSampleResume(UUID.fromString("323e4567-e89b-12d3-a456-426614174000"), USERID, "職務経歴書名2")));

        // 重複する職務経歴書名
        ResumeName resumeName = ResumeName.create(notification, "職務経歴書名1");

        // 重複チェックを実行
        assertThatThrownBy(() -> service.execute(USERID, resumeName)).isInstanceOf(DomainException.class)
                .hasMessage("この職務経歴書名は既に登録されています。");
    }

    @Test
    @DisplayName("同名の職務経歴書名が存在しない場合、DomainExceptionがスローされない")
    void test3() {
        // モックをセットアップ
        when(repository.findAll(USERID)).thenReturn(List.of(
                createSampleResume(UUID.fromString("223e4567-e89b-12d3-a456-426614174000"), USERID, "職務経歴書名1"),
                createSampleResume(UUID.fromString("323e4567-e89b-12d3-a456-426614174000"), USERID, "職務経歴書名2")));

        // チェック対象の職務経歴書名
        ResumeName resumeName = ResumeName.create(notification, "職務経歴書名3");

        // 重複チェックを実行
        assertThatCode(() -> service.execute(USERID, resumeName)).doesNotThrowAnyException();

        // 職務経歴書検索が呼ばれる
        verify(repository, times(1)).findAll(USERID);
    }

    /**
     * プロジェクトのサンプルエンティティを作成する補助メソッド
     */
    private Resume createSampleResume(UUID id, UUID userId, String name) {
        return Resume.reconstruct(
                id,
                userId,
                ResumeName.create(notification, name),
                LocalDate.now(),
                FullName.create(notification, "山田", "太郎"),
                LocalDateTime.now(),
                LocalDateTime.now(),
                List.of(), // careers
                List.of(), // projects
                List.of(), // certifications
                List.of(), // portfolios
                List.of(), // socialLinks
                List.of() // selfPromotions
        );
    }
}
