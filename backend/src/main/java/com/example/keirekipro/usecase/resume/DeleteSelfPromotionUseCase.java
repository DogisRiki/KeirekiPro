package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.shared.exception.ResourceNotFoundUseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 自己PR削除ユースケース
 */
@Service
@RequiredArgsConstructor
public class DeleteSelfPromotionUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 自己PR削除ユースケースを実行する
     *
     * @param userId ユーザーID
     * @param resumeId 職務経歴書ID
     * @param selfPromotionId 自己PRID
     */
    @Transactional
    public void execute(UUID userId, String resumeId, UUID selfPromotionId) {
        UUID resolvedResumeId = ResumeIdResolver.resolve(resumeId);

        Resume resume = resumeRepository.find(resolvedResumeId)
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。");
        }

        boolean exists = resume.getSelfPromotions().stream().anyMatch(s -> s.getId().equals(selfPromotionId));
        if (!exists) {
            throw new ResourceNotFoundUseCaseException("対象の自己PRが存在しません。");
        }

        Resume updated = resume.removeSelfPromotion(selfPromotionId);

        resumeRepository.save(updated);
    }
}
