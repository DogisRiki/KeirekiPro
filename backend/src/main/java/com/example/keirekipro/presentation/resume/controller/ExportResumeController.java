package com.example.keirekipro.presentation.resume.controller;

import java.nio.charset.StandardCharsets;
import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.ExportResumeUseCase;
import com.example.keirekipro.usecase.resume.dto.ExportResumeUseCaseDto;
import com.example.keirekipro.usecase.resume.export.ExportFormat;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書エクスポートコントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class ExportResumeController {

    private final ExportResumeUseCase exportResumeUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 職務経歴書エクスポートエンドポイント
     */
    @GetMapping("/{resumeId}/export")
    @Operation(summary = "職務経歴書エクスポート", description = "職務経歴書をファイルとしてエクスポートしダウンロードする")
    public ResponseEntity<byte[]> handle(
            @PathVariable("resumeId") UUID resumeId,
            @RequestHeader(value = HttpHeaders.ACCEPT, required = false) String accept) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        // Accept ヘッダーからフォーマットを判定する
        ExportFormat format;
        String acceptValue = accept != null ? accept : "";
        if (acceptValue.contains(MediaType.APPLICATION_PDF_VALUE)) {
            format = ExportFormat.PDF;
        } else if (acceptValue.contains("text/markdown")) {
            format = ExportFormat.MARKDOWN;
        } else {
            throw new IllegalStateException("想定外のAcceptです: " + acceptValue);
        }

        ExportResumeUseCaseDto exported = exportResumeUseCase.execute(userId, resumeId, format);

        // ContentDispositionを使い、RFC5987の filename* 形式（UTF-8 percent-encoding）で出力
        ContentDisposition contentDisposition = ContentDisposition.attachment()
                .filename(exported.getFileName(), StandardCharsets.UTF_8)
                .build();

        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(exported.getContentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION, contentDisposition.toString())
                .body(exported.getContent());
    }
}
