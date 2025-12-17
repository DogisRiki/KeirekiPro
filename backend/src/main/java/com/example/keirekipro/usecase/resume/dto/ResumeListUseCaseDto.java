package com.example.keirekipro.usecase.resume.dto;

import java.time.LocalDateTime;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;

import lombok.Builder;
import lombok.Getter;

/**
 * 職務経歴書一覧用ユースケースDTO
 */
@Getter
@Builder
public class ResumeListUseCaseDto {

    private final UUID id;
    private final String resumeName;
    private final LocalDateTime createdAt;
    private final LocalDateTime updatedAt;

    /**
     * ドメインモデルからユースケースDTOへの変換を行う
     *
     * @param resume Resumeエンティティ
     * @return ユースケースDTO
     */
    public static ResumeListUseCaseDto convertToUseCaseDto(Resume resume) {
        return ResumeListUseCaseDto.builder()
                .id(resume.getId())
                .resumeName(resume.getName().getValue())
                .createdAt(resume.getCreatedAt())
                .updatedAt(resume.getUpdatedAt())
                .build();
    }
}
