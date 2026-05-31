package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.resume.command.UpdateCertificationCommand;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.ResourceNotFoundUseCaseException;

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
     * @param command ユースケースコマンド
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UpdateCertificationCommand command) {
        UUID userId = command.getUserId();
        String resumeId = command.getResumeId();
        UUID certificationId = command.getCertificationId();
        UUID resolvedResumeId = ResumeIdResolver.resolve(resumeId);

        Resume resume = resumeRepository.find(resolvedResumeId)
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。");
        }

        Certification existing = resume.getCertifications().stream()
                .filter(c -> c.getId().equals(certificationId))
                .findFirst()
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象の資格が存在しません。"));

        ErrorCollector errorCollector = new ErrorCollector();

        Certification updatedCertification = existing
                .changeName(errorCollector, command.getName())
                .changeDate(errorCollector, command.getDate());

        Resume updated = resume.updateCertification(errorCollector, updatedCertification);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
