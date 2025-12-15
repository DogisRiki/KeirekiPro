package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * SNS削除ユースケース
 */
@Service
@RequiredArgsConstructor
public class DeleteSocialLinkUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * SNS削除ユースケースを実行する
     *
     * @param userId       ユーザーID
     * @param resumeId     職務経歴書ID
     * @param socialLinkId SNSID
     */
    @Transactional
    public void execute(UUID userId, UUID resumeId, UUID socialLinkId) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        boolean exists = resume.getSocialLinks().stream().anyMatch(s -> s.getId().equals(socialLinkId));
        if (!exists) {
            throw new UseCaseException("対象のSNSが存在しません。");
        }

        Resume updated = resume.removeSociealLink(socialLinkId);

        resumeRepository.save(updated);
    }
}
