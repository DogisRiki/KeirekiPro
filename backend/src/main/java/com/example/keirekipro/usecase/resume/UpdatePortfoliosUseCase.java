package com.example.keirekipro.usecase.resume;

import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdatePortfoliosRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書 ポートフォリオ更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdatePortfoliosUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * ポートフォリオ更新ユースケースを実行する
     *
     * @param userId   ユーザーID
     * @param resumeId 職務経歴書ID
     * @param request  リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UpdatePortfoliosRequest request) {

        // 職務経歴書の存在チェック
        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        // 認可チェック（本人の職務経歴書か）
        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        Notification notification = new Notification();

        // 更新中の職務経歴書
        Resume updatedResume = resume;

        // 既存のポートフォリオをIDで引けるようにマッピング
        Map<UUID, Portfolio> remainingPortfoliosById = resume.getPortfolios().stream()
                .collect(Collectors.toMap(Portfolio::getId, Function.identity()));

        // リクエストの内容に従って追加・更新
        for (UpdatePortfoliosRequest.PortfolioRequest portfolioRequest : request.getPortfolios()) {

            Link link = Link.create(notification, portfolioRequest.getLink());

            // 新規追加
            if (portfolioRequest.getId() == null) {
                Portfolio newPortfolio = Portfolio.create(
                        notification,
                        portfolioRequest.getName(),
                        portfolioRequest.getOverview(),
                        portfolioRequest.getTechStack(),
                        link);

                updatedResume = updatedResume.addPortfolio(notification, newPortfolio);
                continue;
            }

            // 既存更新
            Portfolio currentPortfolio = remainingPortfoliosById.remove(portfolioRequest.getId());
            if (currentPortfolio == null) {
                throw new UseCaseException("更新対象のポートフォリオ情報が存在しません。");
            }

            Portfolio updatedPortfolio = currentPortfolio
                    .changeName(notification, portfolioRequest.getName())
                    .changeOverview(notification, portfolioRequest.getOverview())
                    .changeTechStack(notification, portfolioRequest.getTechStack())
                    .changeLink(notification, link);

            updatedResume = updatedResume.updatePortfolio(notification, updatedPortfolio);
        }

        // リクエストに含まれなかったポートフォリオは削除
        for (Portfolio portfolioToDelete : remainingPortfoliosById.values()) {
            updatedResume = updatedResume.removePortfolio(portfolioToDelete.getId());
        }

        resumeRepository.save(updatedResume);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updatedResume);
    }
}
