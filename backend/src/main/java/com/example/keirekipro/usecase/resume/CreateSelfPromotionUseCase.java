package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.resume.command.CreateSelfPromotionCommand;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.resume.policy.ResumeLimitChecker;
import com.example.keirekipro.usecase.shared.exception.ResourceNotFoundUseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 自己PR新規作成ユースケース
 */
@Service
@RequiredArgsConstructor
public class CreateSelfPromotionUseCase {

    private final ResumeRepository resumeRepository;

    private final ResumeLimitChecker resumeLimitChecker;

    /**
     * 自己PR新規作成ユースケースを実行する
     *
     * @param command ユースケースコマンド
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(CreateSelfPromotionCommand command) {
        UUID userId = command.getUserId();
        String resumeId = command.getResumeId();
        UUID resolvedResumeId = ResumeIdResolver.resolve(resumeId);

        // 上限チェック
        resumeLimitChecker.checkSelfPromotionAddAllowed(resolvedResumeId);

        Resume resume = resumeRepository.find(resolvedResumeId)
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。");
        }

        ErrorCollector errorCollector = new ErrorCollector();

        SelfPromotion selfPromotion = SelfPromotion.create(errorCollector, command.getTitle(), command.getContent());

        Resume updated = resume.addSelfPromotion(errorCollector, selfPromotion);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
