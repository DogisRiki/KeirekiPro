package com.example.keirekipro.usecase.resume;

import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateCertificationsRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書 資格更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateCertificationsUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 資格更新ユースケースを実行する
     *
     * @param userId   ユーザーID
     * @param resumeId 職務経歴書ID
     * @param request  リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UpdateCertificationsRequest request) {

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

        // 既存の資格をIDで引けるようにマッピング
        Map<UUID, Certification> remainingCertificationsById = resume.getCertifications().stream()
                .collect(Collectors.toMap(Certification::getId, Function.identity()));

        // リクエストの内容に従って追加・更新
        for (UpdateCertificationsRequest.CertificationRequest certificationRequest : request.getCertifications()) {

            // 新規追加
            if (certificationRequest.getId() == null) {
                Certification newCertification = Certification.create(
                        notification,
                        certificationRequest.getName(),
                        certificationRequest.getDate());

                updatedResume = updatedResume.addCertification(notification, newCertification);
                continue;
            }

            // 既存更新
            Certification currentCertification = remainingCertificationsById.remove(certificationRequest.getId());
            if (currentCertification == null) {
                throw new UseCaseException("更新対象の資格情報が存在しません。");
            }

            Certification updatedCertification = currentCertification
                    .changeName(notification, certificationRequest.getName())
                    .changeDate(notification, certificationRequest.getDate());

            updatedResume = updatedResume.updateCertification(notification, updatedCertification);
        }

        // リクエストに含まれなかった資格は削除
        for (Certification certificationToDelete : remainingCertificationsById.values()) {
            updatedResume = updatedResume.removeCertification(certificationToDelete.getId());
        }

        resumeRepository.save(updatedResume);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updatedResume);
    }
}
