package com.example.keirekipro.usecase.resume;

import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateSelfPromotionsRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書 自己PRタブ更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateSelfPromotionsUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 自己PRタブを更新する
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UpdateSelfPromotionsRequest request) {

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

        // 既存の自己PRをIDで引けるようにマッピング
        Map<UUID, SelfPromotion> remainingSelfPromotionsById = resume.getSelfPromotions().stream()
                .collect(Collectors.toMap(SelfPromotion::getId, Function.identity()));

        // リクエストの内容に従って追加・更新
        for (UpdateSelfPromotionsRequest.SelfPromotionRequest selfPromotionRequest : request.getSelfPromotions()) {

            // 新規追加
            if (selfPromotionRequest.getId() == null) {
                SelfPromotion newSelfPromotion = SelfPromotion.create(
                        notification,
                        selfPromotionRequest.getTitle(),
                        selfPromotionRequest.getContent());

                updatedResume = updatedResume.addSelfPromotion(notification, newSelfPromotion);
                continue;
            }

            // 既存更新
            SelfPromotion currentSelfPromotion = remainingSelfPromotionsById.remove(selfPromotionRequest.getId());
            if (currentSelfPromotion == null) {
                throw new UseCaseException("更新対象の自己PR情報が存在しません。");
            }

            SelfPromotion updatedSelfPromotion = currentSelfPromotion
                    .changeTitle(notification, selfPromotionRequest.getTitle())
                    .changeContent(notification, selfPromotionRequest.getContent());

            updatedResume = updatedResume.updateSelfPromotion(notification, updatedSelfPromotion);
        }

        // リクエストに含まれなかった自己PRは削除
        for (SelfPromotion selfPromotionToDelete : remainingSelfPromotionsById.values()) {
            updatedResume = updatedResume.removeSelfPromotion(selfPromotionToDelete.getId());
        }

        resumeRepository.save(updatedResume);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updatedResume);
    }
}
