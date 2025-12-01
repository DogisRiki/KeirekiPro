package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.ResumeInfoResponse;
import com.example.keirekipro.presentation.resume.dto.UpdateSocialLinksRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.UpdateSocialLinksUseCase;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

import jakarta.validation.Valid;

/**
 * 職務経歴書 ソーシャルリンク更新コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class UpdateSocialLinksController {

    private final UpdateSocialLinksUseCase updateSocialLinksUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * ソーシャルリンク更新エンドポイント
     */
    @PutMapping("/{resumeId}/social-links")
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "職務経歴書 ソーシャルリンク更新", description = "職務経歴書のソーシャルリンクを更新する")
    public ResumeInfoResponse handle(
            @PathVariable("resumeId") String resumeId,
            @Valid @RequestBody UpdateSocialLinksRequest request) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        UUID resumeUuid = UUID.fromString(resumeId);

        return ResumeInfoResponse.convertToResponse(
                updateSocialLinksUseCase.execute(userId, resumeUuid, request));
    }
}
