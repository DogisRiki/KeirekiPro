package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.ResumeInfoResponse;
import com.example.keirekipro.presentation.resume.dto.UpdateSocialLinkRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.UpdateSocialLinkUseCase;

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
 * 職務経歴書 SNS更新コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class UpdateSocialLinkController {

    private final UpdateSocialLinkUseCase updateSocialLinkUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * SNS更新エンドポイント
     */
    @PutMapping("/{resumeId}/social-links/{socialLinkId}")
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "職務経歴書 SNS更新", description = "職務経歴書のSNSを更新する")
    public ResumeInfoResponse handle(
            @PathVariable("resumeId") UUID resumeId,
            @PathVariable("socialLinkId") UUID socialLinkId,
            @Valid @RequestBody UpdateSocialLinkRequest request) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        return ResumeInfoResponse.convertToResponse(
                updateSocialLinkUseCase.execute(userId, resumeId, socialLinkId, request));
    }
}
