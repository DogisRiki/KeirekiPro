package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateResumeBasicRequest;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書 基本情報更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateResumeBasicUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 基本情報更新ユースケースを実行する
     *
     * @param userId   ユーザーID
     * @param resumeId 職務経歴書ID
     * @param request  リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UpdateResumeBasicRequest request) {

        // 職務経歴書の存在チェック
        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        // 認可チェック（本人の職務経歴書か）
        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        ErrorCollector errorCollector = new ErrorCollector();

        ResumeName resumeName = ResumeName.create(errorCollector, request.getResumeName());
        FullName fullName = FullName.create(errorCollector, request.getLastName(), request.getFirstName());

        // オブジェクト更新
        Resume updatedResume = resume
                .changeName(errorCollector, resumeName)
                .changeDate(errorCollector, request.getDate())
                .ChangeFullName(errorCollector, fullName);

        resumeRepository.save(updatedResume);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updatedResume);
    }
}
