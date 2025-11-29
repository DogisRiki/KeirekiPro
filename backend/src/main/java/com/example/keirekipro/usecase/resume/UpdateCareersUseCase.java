package com.example.keirekipro.usecase.resume;

import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.CompanyName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateCareersRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書 職歴更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateCareersUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 職歴更新ユースケースを実行する
     *
     * @param userId   ユーザーID
     * @param resumeId 職務経歴書ID
     * @param request  リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UpdateCareersRequest request) {

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

        // 既存の職歴をIDで引けるようにマッピング
        Map<UUID, Career> remainingCareersById = resume.getCareers().stream()
                .collect(Collectors.toMap(Career::getId, Function.identity()));

        // リクエストの内容に従って追加・更新
        for (UpdateCareersRequest.CareerRequest careerRequest : request.getCareers()) {

            CompanyName companyName = CompanyName.create(notification, careerRequest.getCompanyName());
            Period period = Period.create(
                    notification,
                    careerRequest.getStartDate(),
                    careerRequest.getEndDate(),
                    Boolean.TRUE.equals(careerRequest.getIsActive()));

            // 新規追加
            if (careerRequest.getId() == null) {
                Career newCareer = Career.create(notification, companyName, period);
                updatedResume = updatedResume.addCareer(notification, newCareer);
                continue;
            }

            // 既存更新
            Career currentCareer = remainingCareersById.remove(careerRequest.getId());
            if (currentCareer == null) {
                throw new UseCaseException("更新対象の職歴情報が存在しません。");
            }

            Career updatedCareer = currentCareer
                    .changeCompanyName(notification, companyName)
                    .changePeriod(notification, period);

            updatedResume = updatedResume.updateCareer(notification, updatedCareer);
        }

        // リクエストに含まれなかった職歴は削除
        for (Career careerToDelete : remainingCareersById.values()) {
            updatedResume = updatedResume.removeCareer(careerToDelete.getId());
        }

        resumeRepository.save(updatedResume);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updatedResume);
    }
}
