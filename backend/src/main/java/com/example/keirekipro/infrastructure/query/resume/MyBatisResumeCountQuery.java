package com.example.keirekipro.infrastructure.query.resume;

import java.util.UUID;

import com.example.keirekipro.usecase.query.resume.ResumeCountQuery;

import org.springframework.stereotype.Repository;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書件数取得用クエリ実装
 */
@Repository
@RequiredArgsConstructor
public class MyBatisResumeCountQuery implements ResumeCountQuery {

    private final ResumeQueryMapper mapper;

    @Override
    public int countResumesByUserId(UUID userId) {
        return mapper.countResumesByUserId(userId);
    }

    @Override
    public int countCareersByResumeId(UUID resumeId) {
        return mapper.countCareersByResumeId(resumeId);
    }

    @Override
    public int countProjectsByResumeId(UUID resumeId) {
        return mapper.countProjectsByResumeId(resumeId);
    }

    @Override
    public int countCertificationsByResumeId(UUID resumeId) {
        return mapper.countCertificationsByResumeId(resumeId);
    }

    @Override
    public int countSnsPlatformsByResumeId(UUID resumeId) {
        return mapper.countSnsPlatformsByResumeId(resumeId);
    }

    @Override
    public int countPortfoliosByResumeId(UUID resumeId) {
        return mapper.countPortfoliosByResumeId(resumeId);
    }

    @Override
    public int countSelfPromotionsByResumeId(UUID resumeId) {
        return mapper.countSelfPromotionsByResumeId(resumeId);
    }
}
