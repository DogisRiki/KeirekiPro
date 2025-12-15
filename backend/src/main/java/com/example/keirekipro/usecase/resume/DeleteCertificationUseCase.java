package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 資格削除ユースケース
 */
@Service
@RequiredArgsConstructor
public class DeleteCertificationUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 資格削除ユースケースを実行する
     *
     * @param userId          ユーザーID
     * @param resumeId        職務経歴書ID
     * @param certificationId 資格ID
     */
    @Transactional
    public void execute(UUID userId, UUID resumeId, UUID certificationId) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        boolean exists = resume.getCertifications().stream().anyMatch(c -> c.getId().equals(certificationId));
        if (!exists) {
            throw new UseCaseException("対象の資格が存在しません。");
        }

        Resume updated = resume.removeCertification(certificationId);

        resumeRepository.save(updated);
    }
}
