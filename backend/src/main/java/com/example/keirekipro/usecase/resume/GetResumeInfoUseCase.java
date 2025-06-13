package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書情報取得ユースケース
 */
@Service
@RequiredArgsConstructor
public class GetResumeInfoUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * 職務経歴書情報取得ユースケースを実行する
     *
     * @param resumeId 職務経歴書ID
     * @return 職務経歴書ユースケースDTO
     */
    public ResumeInfoUseCaseDto execute(UUID resumeId) {

        Resume resume = resumeRepository.find(resumeId).orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        return ResumeInfoUseCaseDto.convertToUseCaseDto(resume);
    }
}
