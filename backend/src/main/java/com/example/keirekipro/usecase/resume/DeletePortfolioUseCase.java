package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * ポートフォリオ削除ユースケース
 */
@Service
@RequiredArgsConstructor
public class DeletePortfolioUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * ポートフォリオ削除ユースケースを実行する
     *
     * @param userId      ユーザーID
     * @param resumeId    職務経歴書ID
     * @param portfolioId ポートフォリオID
     */
    @Transactional
    public void execute(UUID userId, UUID resumeId, UUID portfolioId) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        boolean exists = resume.getPortfolios().stream().anyMatch(p -> p.getId().equals(portfolioId));
        if (!exists) {
            throw new UseCaseException("対象のポートフォリオが存在しません。");
        }

        Resume updated = resume.removePortfolio(portfolioId);

        resumeRepository.save(updated);
    }
}
