package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.DeleteSocialLinkUseCase;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書 SNS削除コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class DeleteSocialLinkController {

    private final DeleteSocialLinkUseCase deleteSocialLinkUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * SNS削除エンドポイント
     */
    @DeleteMapping("/{resumeId}/social-links/{socialLinkId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "職務経歴書 SNS削除", description = "職務経歴書のSNSを削除する")
    public void handle(
            @PathVariable("resumeId") UUID resumeId,
            @PathVariable("socialLinkId") UUID socialLinkId) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        deleteSocialLinkUseCase.execute(userId, resumeId, socialLinkId);
    }
}
