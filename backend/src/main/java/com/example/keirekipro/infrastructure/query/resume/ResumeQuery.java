package com.example.keirekipro.infrastructure.query.resume;

import java.util.UUID;

import org.springframework.stereotype.Repository;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書クエリ
 */
@Repository
@RequiredArgsConstructor
public class ResumeQuery {

    private final ResumeQueryMapper resumeQueryMapper;

    /**
     * ユーザーに紐づく職務経歴書数を取得する
     *
     * @param userId ユーザーID
     * @return 職務経歴書数
     */
    public int countResumesByUserId(UUID userId) {
        return resumeQueryMapper.countResumesByUserId(userId);
    }

    /**
     * 職務経歴書に紐づく職歴数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 職歴数
     */
    public int countCareersByResumeId(UUID resumeId) {
        return resumeQueryMapper.countCareersByResumeId(resumeId);
    }

    /**
     * 職務経歴書に紐づくプロジェクト数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return プロジェクト数
     */
    public int countProjectsByResumeId(UUID resumeId) {
        return resumeQueryMapper.countProjectsByResumeId(resumeId);
    }

    /**
     * 職務経歴書に紐づく資格数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 資格数
     */
    public int countCertificationsByResumeId(UUID resumeId) {
        return resumeQueryMapper.countCertificationsByResumeId(resumeId);
    }

    /**
     * 職務経歴書に紐づくSNSプラットフォーム数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return SNSプラットフォーム数
     */
    public int countSnsPlatformsByResumeId(UUID resumeId) {
        return resumeQueryMapper.countSnsPlatformsByResumeId(resumeId);
    }

    /**
     * 職務経歴書に紐づくポートフォリオ数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return ポートフォリオ数
     */
    public int countPortfoliosByResumeId(UUID resumeId) {
        return resumeQueryMapper.countPortfoliosByResumeId(resumeId);
    }

    /**
     * 職務経歴書に紐づく自己PR数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 自己PR数
     */
    public int countSelfPromotionsByResumeId(UUID resumeId) {
        return resumeQueryMapper.countSelfPromotionsByResumeId(resumeId);
    }
}
