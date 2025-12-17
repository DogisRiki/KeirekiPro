package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職歴削除ユースケース
 */
@Service
@RequiredArgsConstructor
public class DeleteCareerUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 職歴削除ユースケースを実行する
     *
     * @param userId   ユーザーID
     * @param resumeId 職務経歴書ID
     * @param careerId 職歴ID
     */
    @Transactional
    public void execute(UUID userId, UUID resumeId, UUID careerId) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        boolean exists = resume.getCareers().stream().anyMatch(c -> c.getId().equals(careerId));
        if (!exists) {
            throw new UseCaseException("対象の職歴が存在しません。");
        }

        Resume updated = resume.removeCareer(careerId);

        resumeRepository.save(updated);
    }
}
