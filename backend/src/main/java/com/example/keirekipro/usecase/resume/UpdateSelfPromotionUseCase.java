package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.resume.command.UpdateSelfPromotionCommand;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.ResourceNotFoundUseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 自己PR更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateSelfPromotionUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 自己PR更新ユースケースを実行する
     *
     * @param command ユースケースコマンド
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UpdateSelfPromotionCommand command) {
        UUID userId = command.getUserId();
        String resumeId = command.getResumeId();
        UUID selfPromotionId = command.getSelfPromotionId();
        UUID resolvedResumeId = ResumeIdResolver.resolve(resumeId);

        Resume resume = resumeRepository.find(resolvedResumeId)
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。");
        }

        SelfPromotion existing = resume.getSelfPromotions().stream()
                .filter(s -> s.getId().equals(selfPromotionId))
                .findFirst()
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象の自己PRが存在しません。"));

        ErrorCollector errorCollector = new ErrorCollector();

        SelfPromotion updatedSelfPromotion = existing
                .changeTitle(errorCollector, command.getTitle())
                .changeContent(errorCollector, command.getContent());

        Resume updated = resume.updateSelfPromotion(errorCollector, updatedSelfPromotion);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
