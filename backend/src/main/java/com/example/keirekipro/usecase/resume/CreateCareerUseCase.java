package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.CreateCareerRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職歴新規作成ユースケース
 */
@Service
@RequiredArgsConstructor
public class CreateCareerUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 職歴新規作成ユースケースを実行する
     *
     * @param userId   ユーザーID
     * @param resumeId 職務経歴書ID
     * @param request  リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, CreateCareerRequest request) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        Notification notification = new Notification();

        CompanyName companyName = CompanyName.create(notification, request.getCompanyName());
        Period period = Period.create(notification, request.getStartDate(), request.getEndDate(),
                request.getIsActive());
        Career career = Career.create(notification, companyName, period);

        Resume updated = resume.addCareer(notification, career);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
