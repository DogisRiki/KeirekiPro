package com.example.keirekipro.usecase.query.resume;

import java.util.UUID;

/**
 * 職務経歴書件数取得用クエリインターフェース
 */
public interface ResumeCountQuery {

    /**
     * ユーザーに紐づく職務経歴書数を取得する
     *
     * @param userId ユーザーID
     * @return 職務経歴書数
     */
    int countResumesByUserId(UUID userId);

    /**
     * 職務経歴書に紐づく職歴数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 職歴数
     */
    int countCareersByResumeId(UUID resumeId);

    /**
     * 職務経歴書に紐づくプロジェクト数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return プロジェクト数
     */
    int countProjectsByResumeId(UUID resumeId);

    /**
     * 職務経歴書に紐づく資格数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 資格数
     */
    int countCertificationsByResumeId(UUID resumeId);

    /**
     * 職務経歴書に紐づくSNSプラットフォーム数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return SNSプラットフォーム数
     */
    int countSnsPlatformsByResumeId(UUID resumeId);

    /**
     * 職務経歴書に紐づくポートフォリオ数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return ポートフォリオ数
     */
    int countPortfoliosByResumeId(UUID resumeId);

    /**
     * 職務経歴書に紐づく自己PR数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 自己PR数
     */
    int countSelfPromotionsByResumeId(UUID resumeId);
}
