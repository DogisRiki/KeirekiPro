package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.resume.command.UpdateCareerCommand;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.ResourceNotFoundUseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職歴更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateCareerUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 職歴更新ユースケースを実行する
     *
     * @param command ユースケースコマンド
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UpdateCareerCommand command) {
        UUID userId = command.getUserId();
        String resumeId = command.getResumeId();
        UUID careerId = command.getCareerId();
        UUID resolvedResumeId = ResumeIdResolver.resolve(resumeId);

        Resume resume = resumeRepository.find(resolvedResumeId)
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new ResourceNotFoundUseCaseException("対象の職務経歴書データが存在しません。");
        }

        Career existing = resume.getCareers().stream()
                .filter(c -> c.getId().equals(careerId))
                .findFirst()
                .orElseThrow(() -> new ResourceNotFoundUseCaseException("対象の職歴が存在しません。"));

        ErrorCollector errorCollector = new ErrorCollector();

        CompanyName companyName = CompanyName.create(errorCollector, command.getCompanyName());
        Period period = Period.create(errorCollector, command.getStartDate(), command.getEndDate(),
                command.getActive());

        Career updatedCareer = existing
                .changeCompanyName(errorCollector, companyName)
                .changePeriod(errorCollector, period);

        Resume updated = resume.updateCareer(errorCollector, updatedCareer);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
