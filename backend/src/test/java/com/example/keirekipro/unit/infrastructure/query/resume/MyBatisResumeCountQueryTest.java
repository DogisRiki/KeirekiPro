package com.example.keirekipro.unit.infrastructure.query.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.UUID;

import com.example.keirekipro.infrastructure.query.resume.MyBatisResumeCountQuery;
import com.example.keirekipro.infrastructure.query.resume.ResumeQueryMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class MyBatisResumeCountQueryTest {

    @Mock
    private ResumeQueryMapper mapper;

    @InjectMocks
    private MyBatisResumeCountQuery query;

    @Test
    @DisplayName("ユーザーに紐づく職務経歴書数を取得できる")
    void test1() {
        // モック準備
        UUID userId = UUID.randomUUID();
        when(mapper.countResumesByUserId(userId)).thenReturn(3);

        // 実行
        int actual = query.countResumesByUserId(userId);

        // 検証
        assertThat(actual).isEqualTo(3);
        verify(mapper).countResumesByUserId(userId);
    }

    @Test
    @DisplayName("職務経歴書に紐づく職歴数を取得できる")
    void test2() {
        // モック準備
        UUID resumeId = UUID.randomUUID();
        when(mapper.countCareersByResumeId(resumeId)).thenReturn(2);

        // 実行
        int actual = query.countCareersByResumeId(resumeId);

        // 検証
        assertThat(actual).isEqualTo(2);
        verify(mapper).countCareersByResumeId(resumeId);
    }

    @Test
    @DisplayName("職務経歴書に紐づくプロジェクト数を取得できる")
    void test3() {
        // モック準備
        UUID resumeId = UUID.randomUUID();
        when(mapper.countProjectsByResumeId(resumeId)).thenReturn(5);

        // 実行
        int actual = query.countProjectsByResumeId(resumeId);

        // 検証
        assertThat(actual).isEqualTo(5);
        verify(mapper).countProjectsByResumeId(resumeId);
    }

    @Test
    @DisplayName("職務経歴書に紐づく資格数を取得できる")
    void test4() {
        // モック準備
        UUID resumeId = UUID.randomUUID();
        when(mapper.countCertificationsByResumeId(resumeId)).thenReturn(4);

        // 実行
        int actual = query.countCertificationsByResumeId(resumeId);

        // 検証
        assertThat(actual).isEqualTo(4);
        verify(mapper).countCertificationsByResumeId(resumeId);
    }

    @Test
    @DisplayName("職務経歴書に紐づくSNSプラットフォーム数を取得できる")
    void test5() {
        // モック準備
        UUID resumeId = UUID.randomUUID();
        when(mapper.countSnsPlatformsByResumeId(resumeId)).thenReturn(3);

        // 実行
        int actual = query.countSnsPlatformsByResumeId(resumeId);

        // 検証
        assertThat(actual).isEqualTo(3);
        verify(mapper).countSnsPlatformsByResumeId(resumeId);
    }

    @Test
    @DisplayName("職務経歴書に紐づくポートフォリオ数を取得できる")
    void test6() {
        // モック準備
        UUID resumeId = UUID.randomUUID();
        when(mapper.countPortfoliosByResumeId(resumeId)).thenReturn(1);

        // 実行
        int actual = query.countPortfoliosByResumeId(resumeId);

        // 検証
        assertThat(actual).isEqualTo(1);
        verify(mapper).countPortfoliosByResumeId(resumeId);
    }

    @Test
    @DisplayName("職務経歴書に紐づく自己PR数を取得できる")
    void test7() {
        // モック準備
        UUID resumeId = UUID.randomUUID();
        when(mapper.countSelfPromotionsByResumeId(resumeId)).thenReturn(6);

        // 実行
        int actual = query.countSelfPromotionsByResumeId(resumeId);

        // 検証
        assertThat(actual).isEqualTo(6);
        verify(mapper).countSelfPromotionsByResumeId(resumeId);
    }
}
