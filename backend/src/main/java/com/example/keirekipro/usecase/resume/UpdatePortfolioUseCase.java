package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdatePortfolioRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

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
     * @param userId      ユーザーID
     * @param resumeId    職務経歴書ID
     * @param portfolioId ポートフォリオID
     * @param request     リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UUID portfolioId, UpdatePortfolioRequest request) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        Portfolio existing = resume.getPortfolios().stream()
                .filter(p -> p.getId().equals(portfolioId))
                .findFirst()
                .orElseThrow(() -> new UseCaseException("対象のポートフォリオが存在しません。"));

        Notification notification = new Notification();

        Link link = Link.create(notification, request.getLink());

        Portfolio updatedPortfolio = existing
                .changeName(notification, request.getName())
                .changeOverview(notification, request.getOverview())
                .changeTechStack(notification, request.getTechStack())
                .changeLink(notification, link);

        Resume updated = resume.updatePortfolio(notification, updatedPortfolio);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
