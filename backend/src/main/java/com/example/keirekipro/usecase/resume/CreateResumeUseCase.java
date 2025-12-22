package com.example.keirekipro.usecase.resume;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeNameDuplicationCheckService;
import com.example.keirekipro.presentation.resume.dto.CreateResumeRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.resume.policy.ResumeLimitChecker;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書新規作成ユースケース
 */
@Service
@RequiredArgsConstructor
public class CreateResumeUseCase {

    private final ResumeRepository resumeRepository;

    private final ResumeNameDuplicationCheckService resumeNameDuplicationCheckService;

    private final ResumeLimitChecker resumeLimitChecker;

    /**
     * 職務経歴書新規作成ユースケースを実行する
     *
     * @param userId  ユーザーID
     * @param request リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, CreateResumeRequest request) {

        // 上限チェック
        resumeLimitChecker.checkResumeCreateAllowed(userId);

        Notification notification = new Notification();

        // 職務経歴書名の重複チェック
        ResumeName resumeName = ResumeName.create(notification, request.getResumeName());
        resumeNameDuplicationCheckService.execute(userId, resumeName);

        // 職務経歴書エンティティ新規構築
        Resume resume = Resume.create(
                notification,
                userId,
                resumeName,
                LocalDate.now(),
                null,
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of(),
                List.of());

        resumeRepository.save(resume);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(resume);
    }
}
