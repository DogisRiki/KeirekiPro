package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.shared.exception.ResourceNotFoundUseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * プロジェクト削除ユースケース
 */
@Service
@RequiredArgsConstructor
public class DeleteProjectUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * プロジェクト削除ユースケースを実行する
     *
     * @param userId ユーザーID
     * @param resumeId 職務経歴書ID
     * @param projectId プロジェクトID
     */
    @Transactional
    public void execute(UUID userId, String resumeId, UUID projectId) {
        UUID resolvedResumeId = ResumeIdResolver.resolve(resumeId);

        Resume resume = resumeRepository.find(resolvedResumeId)
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。");
        }

        boolean exists = resume.getProjects().stream().anyMatch(p -> p.getId().equals(projectId));
        if (!exists) {
            throw new ResourceNotFoundUseCaseException("対象のプロジェクトが存在しません。");
        }

        Resume updated = resume.removeProject(projectId);

        resumeRepository.save(updated);
    }
}
