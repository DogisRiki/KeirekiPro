package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateCertificationRequest;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 資格更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateCertificationUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 資格更新ユースケースを実行する
     *
     * @param userId          ユーザーID
     * @param resumeId        職務経歴書ID
     * @param certificationId 資格ID
     * @param request         リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UUID certificationId,
            UpdateCertificationRequest request) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        Certification existing = resume.getCertifications().stream()
                .filter(c -> c.getId().equals(certificationId))
                .findFirst()
                .orElseThrow(() -> new UseCaseException("対象の資格が存在しません。"));

        ErrorCollector errorCollector = new ErrorCollector();

        Certification updatedCertification = existing
                .changeName(errorCollector, request.getName())
                .changeDate(errorCollector, request.getDate());

        Resume updated = resume.updateCertification(errorCollector, updatedCertification);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
