package com.example.keirekipro.usecase.resume.policy;

import java.util.UUID;

import com.example.keirekipro.usecase.query.resume.ResumeCountQuery;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書および職務経歴書内セクションの件数上限を検証するチェッカー
 */
@Component
@RequiredArgsConstructor
public class ResumeLimitChecker {

    private final ResumeCountQuery resumeCountQuery;

    /**
     * 職務経歴書の新規作成が可能かをチェックする
     *
     * @param userId ユーザーID
     */
    public void checkResumeCreateAllowed(UUID userId) {
        int count = resumeCountQuery.countResumesByUserId(userId);
        if (count >= ResumeLimits.RESUMES_CREATION_LIMIT) {
            throw new UseCaseException(
                    "職務経歴書の作成可能件数の上限に達しているため作成できません。（現在：" + count + "件／上限：" + ResumeLimits.RESUMES_CREATION_LIMIT
                            + "件）");
        }
    }

    /**
     * 職歴の追加が可能かをチェックする
     *
     * @param resumeId 職務経歴書ID
     */
    public void checkCareerAddAllowed(UUID resumeId) {
        int count = resumeCountQuery.countCareersByResumeId(resumeId);
        if (count >= ResumeLimits.CAREERS_CREATION_LIMIT) {
            throw new UseCaseException(
                    "職歴の追加可能件数の上限に達しているため追加できません。（現在：" + count + "件／上限：" + ResumeLimits.CAREERS_CREATION_LIMIT + "件）");
        }
    }

    /**
     * プロジェクトの追加が可能かをチェックする
     *
     * @param resumeId 職務経歴書ID
     */
    public void checkProjectAddAllowed(UUID resumeId) {
        int count = resumeCountQuery.countProjectsByResumeId(resumeId);
        if (count >= ResumeLimits.PROJECTS_CREATION_LIMIT) {
            throw new UseCaseException(
                    "プロジェクトの追加可能件数の上限に達しているため追加できません。（現在：" + count + "件／上限：" + ResumeLimits.PROJECTS_CREATION_LIMIT
                            + "件）");
        }
    }

    /**
     * 資格の追加が可能かをチェックする
     *
     * @param resumeId 職務経歴書ID
     */
    public void checkCertificationAddAllowed(UUID resumeId) {
        int count = resumeCountQuery.countCertificationsByResumeId(resumeId);
        if (count >= ResumeLimits.CERTIFICATIONS_CREATION_LIMIT) {
            throw new UseCaseException(
                    "資格の追加可能件数の上限に達しているため追加できません。（現在：" + count + "件／上限：" + ResumeLimits.CERTIFICATIONS_CREATION_LIMIT
                            + "件）");
        }
    }

    /**
     * SNSプラットフォームの追加が可能かをチェックする
     *
     * @param resumeId 職務経歴書ID
     */
    public void checkSnsPlatformAddAllowed(UUID resumeId) {
        int count = resumeCountQuery.countSnsPlatformsByResumeId(resumeId);
        if (count >= ResumeLimits.SNS_PLATFORMS_CREATION_LIMIT) {
            throw new UseCaseException(
                    "SNSプラットフォームの追加可能件数の上限に達しているため追加できません。（現在：" + count + "件／上限："
                            + ResumeLimits.SNS_PLATFORMS_CREATION_LIMIT + "件）");
        }
    }

    /**
     * ポートフォリオの追加が可能かをチェックする
     *
     * @param resumeId 職務経歴書ID
     */
    public void checkPortfolioAddAllowed(UUID resumeId) {
        int count = resumeCountQuery.countPortfoliosByResumeId(resumeId);
        if (count >= ResumeLimits.PORTFOLIOS_CREATION_LIMIT) {
            throw new UseCaseException(
                    "ポートフォリオの追加可能件数の上限に達しているため追加できません。（現在：" + count + "件／上限：" + ResumeLimits.PORTFOLIOS_CREATION_LIMIT
                            + "件）");
        }
    }

    /**
     * 自己PRの追加が可能かをチェックする
     *
     * @param resumeId 職務経歴書ID
     */
    public void checkSelfPromotionAddAllowed(UUID resumeId) {
        int count = resumeCountQuery.countSelfPromotionsByResumeId(resumeId);
        if (count >= ResumeLimits.SELF_PROMOTIONS_CREATION_LIMIT) {
            throw new UseCaseException(
                    "自己PRの追加可能件数の上限に達しているため追加できません。（現在：" + count + "件／上限：" + ResumeLimits.SELF_PROMOTIONS_CREATION_LIMIT
                            + "件）");
        }
    }
}
