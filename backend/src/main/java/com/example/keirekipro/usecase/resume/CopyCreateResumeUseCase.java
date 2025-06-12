package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.service.resume.ResumeNameDuplicationCheckService;
import com.example.keirekipro.presentation.resume.dto.CreateResumeRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書コピーして新規作成ユースケース
 */
@Service
@RequiredArgsConstructor
public class CopyCreateResumeUseCase {

    private final ResumeRepository resumeRepository;

    private final ResumeNameDuplicationCheckService resumeNameDuplicationCheckService;

    /**
     * 職務経歴書コピーして新規作成ユースケースを実行する
     *
     * @param userId  ユーザーID
     * @param request リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, CreateResumeRequest request) {

        Notification notification = new Notification();

        // 職務経歴書名の重複チェック
        ResumeName resumeName = ResumeName.create(notification, request.getResumeName());
        resumeNameDuplicationCheckService.execute(userId, resumeName);

        // コピー元を取得
        Resume source = resumeRepository.find(request.getResumeId())
                .orElseThrow(() -> new UseCaseException("コピー元の職務経歴書が存在しません。"));

        // 職務経歴書エンティティ新規構築
        Resume copy = Resume.create(
                notification,
                userId,
                resumeName,
                source.getDate(),
                source.getFullName(),
                source.getCareers(),
                source.getProjects(),
                source.getCertifications(),
                source.getPortfolios(),
                source.getSocialLinks(),
                source.getSelfPromotions());

        resumeRepository.save(copy);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(copy);
    }
}
