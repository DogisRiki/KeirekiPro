package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.SnsPlatform;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateSnsPlatformRequest;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * SNSプラットフォーム更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateSnsPlatformUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * SNS更新ユースケースを実行する
     *
     * @param userId        ユーザーID
     * @param resumeId      職務経歴書ID
     * @param snsPlatFormId SNSプラットフォームID
     * @param request       リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UUID snsPlatFormId,
            UpdateSnsPlatformRequest request) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        SnsPlatform existing = resume.getSnsPlatforms().stream()
                .filter(s -> s.getId().equals(snsPlatFormId))
                .findFirst()
                .orElseThrow(() -> new UseCaseException("対象のSNSプラットフォームが存在しません。"));

        ErrorCollector errorCollector = new ErrorCollector();

        Link link = Link.create(errorCollector, request.getLink());

        SnsPlatform updatedSnsPlatform = existing
                .changeName(errorCollector, request.getName())
                .changeLink(errorCollector, link);

        Resume updated = resume.updateSnsPlatform(errorCollector, updatedSnsPlatform);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
