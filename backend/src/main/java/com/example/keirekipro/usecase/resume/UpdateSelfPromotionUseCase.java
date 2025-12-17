package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateSelfPromotionRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

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
     * @param userId          ユーザーID
     * @param resumeId        職務経歴書ID
     * @param selfPromotionId 自己PRID
     * @param request         リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UUID selfPromotionId,
            UpdateSelfPromotionRequest request) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        SelfPromotion existing = resume.getSelfPromotions().stream()
                .filter(s -> s.getId().equals(selfPromotionId))
                .findFirst()
                .orElseThrow(() -> new UseCaseException("対象の自己PRが存在しません。"));

        Notification notification = new Notification();

        SelfPromotion updatedSelfPromotion = existing
                .changeTitle(notification, request.getTitle())
                .changeContent(notification, request.getContent());

        Resume updated = resume.updateSelfPromotion(notification, updatedSelfPromotion);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
