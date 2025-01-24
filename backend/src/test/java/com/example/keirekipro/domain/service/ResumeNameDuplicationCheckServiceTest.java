package com.example.keirekipro.domain.service;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeNameDuplicationCheckService;
import com.example.keirekipro.domain.shared.Notification;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class ResumeNameDuplicationCheckServiceTest {

    @Mock
    private ResumeRepository repository;

    @Mock
    private Notification notification;

    @InjectMocks
    private ResumeNameDuplicationCheckService service;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    @DisplayName("同名の職務経歴書名が存在しない")
    void test1() {
        when(repository.findAll("userA")).thenReturn(List.of(
                createSampleResume("aaaa", "userA", "職務経歴書名1"),
                createSampleResume("bbbb", "userA", "職務経歴書名2")));

        // 重複しない職務経歴書名
        Resume target = createSampleResume("cccc", "userA", "職務経歴書名3");

        boolean result = service.execute(target);

        // 重複がないため、falseとなる。
        assertFalse(result);
    }

    @Test
    @DisplayName("同名の職務経歴書が存在する")
    void test2() {
        when(repository.findAll("userA")).thenReturn(List.of(
                createSampleResume("aaaa", "userA", "職務経歴書名1"),
                createSampleResume("bbbb", "userA", "職務経歴書名2")));

        // 重複する職務経歴書名
        Resume target = createSampleResume("cccc", "userA", "職務経歴書名1");

        boolean result = service.execute(target);

        // 重複するため、trueとなる。
        assertTrue(result);
    }

    @Test
    @DisplayName("自分自身は除外される(同じIDで同じ名前があっても重複とみなさない)")
    void test3() {
        when(repository.findAll("userA")).thenReturn(List.of(
                createSampleResume("aaaa", "userA", "職務経歴書名1"),
                createSampleResume("bbbb", "userA", "職務経歴書名2")));

        // 同一の職務経歴書IDに対して行う
        Resume target = createSampleResume("aaaa", "userA", "職務経歴書名1");

        boolean result = service.execute(target);

        // 重複とみなされないため、falseとなる。
        assertFalse(result);
    }

    /**
     * プロジェクトのサンプルエンティティを作成する補助メソッド
     */
    private Resume createSampleResume(String id, String userId, String resumeName) {
        return Resume.reconstruct(
                id,
                0,
                userId,
                ResumeName.create(notification, resumeName),
                LocalDate.now(),
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
