package com.example.keirekipro.infrastructure.query.resume;

import java.util.UUID;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * 職務経歴書クエリマッパー
 */
@Mapper
public interface ResumeQueryMapper {

    /**
     * 職務経歴書数を取得する
     *
     * @param userId ユーザーID
     * @return 職務経歴書数
     */
    int countResumesByUserId(@Param("userId") UUID userId);

    /**
     * 職務経歴書に紐づく職歴数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 職歴数
     */
    int countCareersByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 職務経歴書に紐づくプロジェクト数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return プロジェクト数
     */
    int countProjectsByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 職務経歴書に紐づく資格数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 資格数
     */
    int countCertificationsByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 職務経歴書に紐づくSNSプラットフォーム数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return SNSプラットフォーム数
     */
    int countSnsPlatformsByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 職務経歴書に紐づくポートフォリオ数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return ポートフォリオ数
     */
    int countPortfoliosByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 職務経歴書に紐づく自己PR数を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 自己PR数
     */
    int countSelfPromotionsByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * バックアップ用に職務経歴書データをJSON文字列として取得する
     *
     * @param resumeId 職務経歴書ID
     * @param userId   ユーザーID
     * @return 職務経歴書データのJSON文字列
     */
    String selectResumeForBackup(@Param("resumeId") UUID resumeId, @Param("userId") UUID userId);
}
