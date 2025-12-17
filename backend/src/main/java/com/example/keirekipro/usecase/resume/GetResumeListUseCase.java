package com.example.keirekipro.usecase.resume;

import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.resume.dto.ResumeListUseCaseDto;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書一覧取得ユースケース
 */
@Service
@RequiredArgsConstructor
public class GetResumeListUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 職務経歴書一覧取得ユースケースを実行する
     *
     * @param userId ユーザーID
     * @return 職務経歴書一覧DTO
     */
    public List<ResumeListUseCaseDto> execute(UUID userId) {
        return resumeRepository.findAll(userId).stream()
                .map(ResumeListUseCaseDto::convertToUseCaseDto)
                .toList();
    }
}
