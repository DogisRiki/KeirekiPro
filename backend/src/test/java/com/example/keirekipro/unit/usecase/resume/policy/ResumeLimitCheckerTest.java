package com.example.keirekipro.unit.usecase.resume.policy;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.UUID;

import com.example.keirekipro.usecase.query.resume.ResumeCountQuery;
import com.example.keirekipro.usecase.resume.policy.ResumeLimitChecker;
import com.example.keirekipro.usecase.resume.policy.ResumeLimits;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ResumeLimitCheckerTest {

    @Mock
    private ResumeCountQuery resumeCountQuery;

    @InjectMocks
    private ResumeLimitChecker checker;

    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RESUME_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");

    @Test
    @DisplayName("checkResumeCreateAllowed_上限未満の場合、例外をスローしない")
    void test1() {
        when(resumeCountQuery.countResumesByUserId(USER_ID))
                .thenReturn(ResumeLimits.RESUMES_CREATION_LIMIT - 1);

        checker.checkResumeCreateAllowed(USER_ID);

        verify(resumeCountQuery).countResumesByUserId(USER_ID);
    }

    @Test
    @DisplayName("checkResumeCreateAllowed_上限以上の場合、UseCaseExceptionをスローする")
    void test2() {
        int count = ResumeLimits.RESUMES_CREATION_LIMIT;
        when(resumeCountQuery.countResumesByUserId(USER_ID)).thenReturn(count);

        String expected = "職務経歴書の作成可能件数の上限に達しているため作成できません。（現在：" + count + "件／上限："
                + ResumeLimits.RESUMES_CREATION_LIMIT + "件）";

        assertThatThrownBy(() -> checker.checkResumeCreateAllowed(USER_ID))
                .isInstanceOf(UseCaseException.class)
                .hasMessage(expected);

        verify(resumeCountQuery).countResumesByUserId(USER_ID);
    }

    @Test
    @DisplayName("checkCareerAddAllowed_上限未満の場合、例外をスローしない")
    void test3() {
        when(resumeCountQuery.countCareersByResumeId(RESUME_ID))
                .thenReturn(ResumeLimits.CAREERS_CREATION_LIMIT - 1);

        checker.checkCareerAddAllowed(RESUME_ID);

        verify(resumeCountQuery).countCareersByResumeId(RESUME_ID);
    }

    @Test
    @DisplayName("checkCareerAddAllowed_上限以上の場合、UseCaseExceptionをスローする")
    void test4() {
        int count = ResumeLimits.CAREERS_CREATION_LIMIT;
        when(resumeCountQuery.countCareersByResumeId(RESUME_ID)).thenReturn(count);

        String expected = "職歴の追加可能件数の上限に達しているため追加できません。（現在：" + count + "件／上限："
                + ResumeLimits.CAREERS_CREATION_LIMIT + "件）";

        assertThatThrownBy(() -> checker.checkCareerAddAllowed(RESUME_ID))
                .isInstanceOf(UseCaseException.class)
                .hasMessage(expected);

        verify(resumeCountQuery).countCareersByResumeId(RESUME_ID);
    }

    @Test
    @DisplayName("checkProjectAddAllowed_上限未満の場合、例外をスローしない")
    void test5() {
        when(resumeCountQuery.countProjectsByResumeId(RESUME_ID))
                .thenReturn(ResumeLimits.PROJECTS_CREATION_LIMIT - 1);

        checker.checkProjectAddAllowed(RESUME_ID);

        verify(resumeCountQuery).countProjectsByResumeId(RESUME_ID);
    }

    @Test
    @DisplayName("checkProjectAddAllowed_上限以上の場合、UseCaseExceptionをスローする")
    void test6() {
        int count = ResumeLimits.PROJECTS_CREATION_LIMIT;
        when(resumeCountQuery.countProjectsByResumeId(RESUME_ID)).thenReturn(count);

        String expected = "プロジェクトの追加可能件数の上限に達しているため追加できません。（現在：" + count + "件／上限："
                + ResumeLimits.PROJECTS_CREATION_LIMIT + "件）";

        assertThatThrownBy(() -> checker.checkProjectAddAllowed(RESUME_ID))
                .isInstanceOf(UseCaseException.class)
                .hasMessage(expected);

        verify(resumeCountQuery).countProjectsByResumeId(RESUME_ID);
    }

    @Test
    @DisplayName("checkCertificationAddAllowed_上限未満の場合、例外をスローしない")
    void test7() {
        when(resumeCountQuery.countCertificationsByResumeId(RESUME_ID))
                .thenReturn(ResumeLimits.CERTIFICATIONS_CREATION_LIMIT - 1);

        checker.checkCertificationAddAllowed(RESUME_ID);

        verify(resumeCountQuery).countCertificationsByResumeId(RESUME_ID);
    }

    @Test
    @DisplayName("checkCertificationAddAllowed_上限以上の場合、UseCaseExceptionをスローする")
    void test8() {
        int count = ResumeLimits.CERTIFICATIONS_CREATION_LIMIT;
        when(resumeCountQuery.countCertificationsByResumeId(RESUME_ID)).thenReturn(count);

        String expected = "資格の追加可能件数の上限に達しているため追加できません。（現在：" + count + "件／上限："
                + ResumeLimits.CERTIFICATIONS_CREATION_LIMIT + "件）";

        assertThatThrownBy(() -> checker.checkCertificationAddAllowed(RESUME_ID))
                .isInstanceOf(UseCaseException.class)
                .hasMessage(expected);

        verify(resumeCountQuery).countCertificationsByResumeId(RESUME_ID);
    }

    @Test
    @DisplayName("checkSnsPlatformAddAllowed_上限未満の場合、例外をスローしない")
    void test9() {
        when(resumeCountQuery.countSnsPlatformsByResumeId(RESUME_ID))
                .thenReturn(ResumeLimits.SNS_PLATFORMS_CREATION_LIMIT - 1);

        checker.checkSnsPlatformAddAllowed(RESUME_ID);

        verify(resumeCountQuery).countSnsPlatformsByResumeId(RESUME_ID);
    }

    @Test
    @DisplayName("checkSnsPlatformAddAllowed_上限以上の場合、UseCaseExceptionをスローする")
    void test10() {
        int count = ResumeLimits.SNS_PLATFORMS_CREATION_LIMIT;
        when(resumeCountQuery.countSnsPlatformsByResumeId(RESUME_ID)).thenReturn(count);

        String expected = "SNSプラットフォームの追加可能件数の上限に達しているため追加できません。（現在：" + count + "件／上限："
                + ResumeLimits.SNS_PLATFORMS_CREATION_LIMIT + "件）";

        assertThatThrownBy(() -> checker.checkSnsPlatformAddAllowed(RESUME_ID))
                .isInstanceOf(UseCaseException.class)
                .hasMessage(expected);

        verify(resumeCountQuery).countSnsPlatformsByResumeId(RESUME_ID);
    }

    @Test
    @DisplayName("checkPortfolioAddAllowed_上限未満の場合、例外をスローしない")
    void test11() {
        when(resumeCountQuery.countPortfoliosByResumeId(RESUME_ID))
                .thenReturn(ResumeLimits.PORTFOLIOS_CREATION_LIMIT - 1);

        checker.checkPortfolioAddAllowed(RESUME_ID);

        verify(resumeCountQuery).countPortfoliosByResumeId(RESUME_ID);
    }

    @Test
    @DisplayName("checkPortfolioAddAllowed_上限以上の場合、UseCaseExceptionをスローする")
    void test12() {
        int count = ResumeLimits.PORTFOLIOS_CREATION_LIMIT;
        when(resumeCountQuery.countPortfoliosByResumeId(RESUME_ID)).thenReturn(count);

        String expected = "ポートフォリオの追加可能件数の上限に達しているため追加できません。（現在：" + count + "件／上限："
                + ResumeLimits.PORTFOLIOS_CREATION_LIMIT + "件）";

        assertThatThrownBy(() -> checker.checkPortfolioAddAllowed(RESUME_ID))
                .isInstanceOf(UseCaseException.class)
                .hasMessage(expected);

        verify(resumeCountQuery).countPortfoliosByResumeId(RESUME_ID);
    }

    @Test
    @DisplayName("checkSelfPromotionAddAllowed_上限未満の場合、例外をスローしない")
    void test13() {
        when(resumeCountQuery.countSelfPromotionsByResumeId(RESUME_ID))
                .thenReturn(ResumeLimits.SELF_PROMOTIONS_CREATION_LIMIT - 1);

        checker.checkSelfPromotionAddAllowed(RESUME_ID);

        verify(resumeCountQuery).countSelfPromotionsByResumeId(RESUME_ID);
    }

    @Test
    @DisplayName("checkSelfPromotionAddAllowed_上限以上の場合、UseCaseExceptionをスローする")
    void test14() {
        int count = ResumeLimits.SELF_PROMOTIONS_CREATION_LIMIT;
        when(resumeCountQuery.countSelfPromotionsByResumeId(RESUME_ID)).thenReturn(count);

        String expected = "自己PRの追加可能件数の上限に達しているため追加できません。（現在：" + count + "件／上限："
                + ResumeLimits.SELF_PROMOTIONS_CREATION_LIMIT + "件）";

        assertThatThrownBy(() -> checker.checkSelfPromotionAddAllowed(RESUME_ID))
                .isInstanceOf(UseCaseException.class)
                .hasMessage(expected);

        verify(resumeCountQuery).countSelfPromotionsByResumeId(RESUME_ID);
    }
}
