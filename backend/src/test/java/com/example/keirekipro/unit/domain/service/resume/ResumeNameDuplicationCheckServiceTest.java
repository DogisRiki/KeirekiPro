package com.example.keirekipro.unit.domain.service.resume;

import static org.assertj.core.api.Assertions.assertThat;
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
    @DisplayName("同名の職務経歴書名が存在しない")
    void test1() {
        // モックをセットアップ
        when(repository.findAll(
                USERID)).thenReturn(List.of(
                        createSampleResume(UUID.fromString("223e4567-e89b-12d3-a456-426614174000"),
                                USERID, "職務経歴書名1"),
                        createSampleResume(UUID.fromString("323e4567-e89b-12d3-a456-426614174000"),
                                USERID, "職務経歴書名2")));

        // 重複しない職務経歴書名
        Resume target = createSampleResume(UUID.fromString("423e4567-e89b-12d3-a456-426614174000"), USERID, "職務経歴書名3");

        boolean result = service.execute(target);

        // 重複がないため、falseとなる
        assertThat(result).isFalse();
    }

    @Test
    @DisplayName("同名の職務経歴書が存在する")
    void test2() {
        // モックをセットアップ
        when(repository.findAll(
                USERID)).thenReturn(List.of(
                        createSampleResume(UUID.fromString("223e4567-e89b-12d3-a456-426614174000"),
                                USERID, "職務経歴書名1"),
                        createSampleResume(UUID.fromString("323e4567-e89b-12d3-a456-426614174000"), USERID,
                                "職務経歴書名2")));

        // 重複する職務経歴書名
        Resume target = createSampleResume(UUID.fromString("423e4567-e89b-12d3-a456-426614174000"), USERID, "職務経歴書名1");

        boolean result = service.execute(target);

        // 重複するため、trueとなる
        assertThat(result).isTrue();
    }

    @Test
    @DisplayName("自分自身は除外される(同じIDで同じ名前があっても重複とみなさない)")
    void test3() {
        // モックをセットアップ
        when(repository.findAll(
                USERID)).thenReturn(List.of(
                        createSampleResume(UUID.fromString("223e4567-e89b-12d3-a456-426614174000"),
                                USERID, "職務経歴書名1"),
                        createSampleResume(UUID.fromString("323e4567-e89b-12d3-a456-426614174000"), USERID,
                                "職務経歴書名2")));

        // 同一の職務経歴書IDに対して行う
        Resume target = createSampleResume(UUID.fromString("223e4567-e89b-12d3-a456-426614174000"), USERID, "職務経歴書名1");

        boolean result = service.execute(target);

        // 重複とみなされないため、falseとなる
        assertThat(result).isFalse();
    }

    /**
     * プロジェクトのサンプルエンティティを作成する補助メソッド
     */
    private Resume createSampleResume(UUID id, UUID userId, String resumeName) {
        return Resume.reconstruct(
                id,
                userId,
                ResumeName.create(notification, resumeName),
                LocalDate.now(),
                FullName.create(notification, "山田", "太郎"),
                false,
                LocalDateTime.now(),
                LocalDateTime.now(),
                List.of(), // careers
                List.of(), // projects
                List.of(), // certifications
                List.of(), // portfolios
                List.of(), // sociealLinks
                List.of() // selfPromotions
        );
    }
}
