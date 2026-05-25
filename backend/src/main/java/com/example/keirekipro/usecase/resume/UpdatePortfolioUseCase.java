package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdatePortfolioRequest;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.ResourceNotFoundUseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * ポートフォリオ更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdatePortfolioUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * ポートフォリオ更新ユースケースを実行する
     *
     * @param userId ユーザーID
     * @param resumeId 職務経歴書ID
     * @param portfolioId ポートフォリオID
     * @param request リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, String resumeId, UUID portfolioId,
            UpdatePortfolioRequest request) {
        UUID resolvedResumeId = ResumeIdResolver.resolve(resumeId);

        Resume resume = resumeRepository.find(resolvedResumeId)
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。");
        }

        Portfolio existing = resume.getPortfolios().stream()
                .filter(p -> p.getId().equals(portfolioId))
                .findFirst()
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象のポートフォリオが存在しません。"));

        ErrorCollector errorCollector = new ErrorCollector();

        Link link = Link.create(errorCollector, request.getLink());

        Portfolio updatedPortfolio = existing
                .changeName(errorCollector, request.getName())
                .changeOverview(errorCollector, request.getOverview())
                .changeTechStack(errorCollector, request.getTechStack())
                .changeLink(errorCollector, link);

        Resume updated = resume.updatePortfolio(errorCollector, updatedPortfolio);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
