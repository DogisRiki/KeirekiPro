package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateCareerRequest;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

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
     * @param userId   ユーザーID
     * @param resumeId 職務経歴書ID
     * @param careerId 職歴ID
     * @param request  リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UUID careerId, UpdateCareerRequest request) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        Career existing = resume.getCareers().stream()
                .filter(c -> c.getId().equals(careerId))
                .findFirst()
                .orElseThrow(() -> new UseCaseException("対象の職歴が存在しません。"));

        ErrorCollector errorCollector = new ErrorCollector();

        CompanyName companyName = CompanyName.create(errorCollector, request.getCompanyName());
        Period period = Period.create(errorCollector, request.getStartDate(), request.getEndDate(),
                request.getIsActive());

        Career updatedCareer = existing
                .changeCompanyName(errorCollector, companyName)
                .changePeriod(errorCollector, period);

        Resume updated = resume.updateCareer(errorCollector, updatedCareer);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
