package com.example.keirekipro.presentation.resume.controller;

import java.nio.charset.StandardCharsets;
import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.BackupResumeResponse;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.BackupResumeUseCase;
import com.example.keirekipro.usecase.resume.dto.BackupResumeUseCaseDto;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書バックアップコントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class BackupResumeController {

    private final BackupResumeUseCase backupResumeUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 職務経歴書バックアップエンドポイント
     *
     * @param resumeId 職務経歴書ID
     * @return バックアップJSONレスポンス
     */
    @GetMapping("/{resumeId}/backup")
    @Operation(summary = "職務経歴書バックアップ", description = "職務経歴書をJSON形式でバックアップする")
    public ResponseEntity<BackupResumeResponse> handle(@PathVariable("resumeId") UUID resumeId) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        BackupResumeUseCaseDto useCaseDto = backupResumeUseCase.execute(userId, resumeId);

        BackupResumeResponse response = BackupResumeResponse.convertToResponse(useCaseDto);

        // ContentDispositionを使い、RFC5987の filename* 形式（UTF-8 percent-encoding）で出力
        ContentDisposition contentDisposition = ContentDisposition.attachment()
                .filename(useCaseDto.getFileName(), StandardCharsets.UTF_8)
                .build();

        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(useCaseDto.getContentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION, contentDisposition.toString())
                .body(response);
    }
}
