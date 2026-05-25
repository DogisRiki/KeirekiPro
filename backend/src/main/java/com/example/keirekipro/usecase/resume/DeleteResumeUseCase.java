package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.shared.exception.ResourceNotFoundUseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書削除ユースケース
 */
@Service
@RequiredArgsConstructor
public class DeleteResumeUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 職務経歴書削除ユースケースを実行する
     *
     * @param userId ユーザーID
     * @param resumeId 職務経歴書ID
     */
    @Transactional
    public void execute(UUID userId, String resumeId) {
        UUID resolvedResumeId = ResumeIdResolver.resolve(resumeId);

        // 職務経歴書の存在チェック
        Resume resume = resumeRepository.find(resolvedResumeId)
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。"));

        // 認可チェック（本人の職務経歴書か）
        if (!resume.getUserId().equals(userId)) {
            throw new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。");
        }

        // 職務経歴書削除
        resumeRepository.delete(resolvedResumeId);
    }
}
