package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.shared.exception.ResourceNotFoundUseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * SNSプラットフォーム削除ユースケース
 */
@Service
@RequiredArgsConstructor
public class DeleteSnsPlatformUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * SNSプラットフォーム削除ユースケースを実行する
     *
     * @param userId ユーザーID
     * @param resumeId 職務経歴書ID
     * @param snsPlatformId SNSプラットフォームID
     */
    @Transactional
    public void execute(UUID userId, String resumeId, UUID snsPlatformId) {
        UUID resolvedResumeId = ResumeIdResolver.resolve(resumeId);

        Resume resume = resumeRepository.find(resolvedResumeId)
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。");
        }

        boolean exists = resume.getSnsPlatforms().stream().anyMatch(s -> s.getId().equals(snsPlatformId));
        if (!exists) {
            throw new ResourceNotFoundUseCaseException("対象のSNSプラットフォームが存在しません。");
        }

        Resume updated = resume.removeSnsPlatform(snsPlatformId);

        resumeRepository.save(updated);
    }
}
