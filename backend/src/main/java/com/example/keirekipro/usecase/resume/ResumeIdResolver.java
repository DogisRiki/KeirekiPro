package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.usecase.shared.exception.ResourceNotFoundUseCaseException;

/**
 * API境界で受け取った職務経歴書IDを内部IDへ解決する
 */
public final class ResumeIdResolver {

    private static final String RESUME_NOT_FOUND_MESSAGE = "対象の職務経歴書データが存在しません。";

    private ResumeIdResolver() {
    }

    /**
     * 職務経歴書IDをUUIDへ解決する
     *
     * @param resumeId 職務経歴書ID
     * @return 内部で利用するUUID
     */
    public static UUID resolve(String resumeId) {
        try {
            return UUID.fromString(resumeId);
        } catch (IllegalArgumentException ignored) {
            throw new ResourceNotFoundUseCaseException(RESUME_NOT_FOUND_MESSAGE);
        }
    }
}
