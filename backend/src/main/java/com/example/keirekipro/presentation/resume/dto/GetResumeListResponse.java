package com.example.keirekipro.presentation.resume.dto;

import java.time.LocalDateTime;
import java.util.List;
import java.util.stream.Collectors;

import com.example.keirekipro.usecase.resume.dto.ResumeListUseCaseDto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;

/**
 * 職務経歴書一覧レスポンスDTO
 */
@Getter
@Builder
@AllArgsConstructor
public class GetResumeListResponse {

    private final List<ResumeSummary> resumes;

    /**
     * ユースケースDTOからレスポンスへの変換を行う
     */
    public static GetResumeListResponse convertToResponse(List<ResumeListUseCaseDto> dtos) {
        return GetResumeListResponse.builder()
                .resumes(dtos.stream()
                        .map(d -> new ResumeSummary(
                                d.getId().toString(),
                                d.getResumeName(),
                                d.getCreatedAt(),
                                d.getUpdatedAt()))
                        .collect(Collectors.toList()))
                .build();
    }

    /**
     * 職務経歴書サマリ
     */
    @Getter
    @AllArgsConstructor
    public static class ResumeSummary {
        private final String id;
        private final String resumeName;
        private final LocalDateTime createdAt;
        private final LocalDateTime updatedAt;
    }
}
