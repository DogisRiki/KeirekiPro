package com.example.keirekipro.presentation.resume.controller;

import java.nio.charset.StandardCharsets;
import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.ExportResumeRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.ExportResumeUseCase;
import com.example.keirekipro.usecase.resume.command.ExportResumeCommand.ExportDisposition;
import com.example.keirekipro.usecase.resume.dto.ExportResumeUseCaseDto;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

/**
 * 明示的なエクスポート設定を含む職務経歴書エクスポートリクエストを扱うコントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class ExportResumeWithSettingsController {

    private final ExportResumeUseCase exportResumeUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 指定された設定で職務経歴書をエクスポートする
     *
     * @param resumeId 職務経歴書ID
     * @param request エクスポート設定リクエスト
     * @return エクスポートされた職務経歴書ファイルレスポンス
     */
    @PostMapping("/{resumeId}/export")
    @Operation(summary = "職務経歴書エクスポート", description = "職務経歴書を指定された設定でエクスポートする")
    public ResponseEntity<byte[]> handle(
            @PathVariable("resumeId") String resumeId,
            @Valid @RequestBody ExportResumeRequest request) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        var command = request.toCommand();
        ExportResumeUseCaseDto exported = exportResumeUseCase.execute(userId, resumeId, command);

        ContentDisposition contentDisposition = buildContentDisposition(exported.getFileName(),
                command.getDisposition());

        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(exported.getContentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION, contentDisposition.toString())
                .body(exported.getContent());
    }

    private ContentDisposition buildContentDisposition(String fileName, ExportDisposition disposition) {
        ContentDisposition.Builder builder = disposition == ExportDisposition.INLINE
                ? ContentDisposition.inline()
                : ContentDisposition.attachment();
        return builder.filename(fileName, StandardCharsets.UTF_8).build();
    }
}
