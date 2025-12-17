package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.ResumeInfoResponse;
import com.example.keirekipro.presentation.resume.dto.UpdateResumeBasicRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.UpdateResumeBasicUseCase;

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
 * 職務経歴書 基本情報更新コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class UpdateResumeBasicController {

    private final UpdateResumeBasicUseCase updateResumeBasicUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 基本情報更新エンドポイント
     */
    @PutMapping("/{resumeId}/basic")
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "職務経歴書 基本情報更新", description = "職務経歴書の基本情報を更新する")
    public ResumeInfoResponse handle(
            @PathVariable("resumeId") String resumeId,
            @Valid @RequestBody UpdateResumeBasicRequest request) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        UUID resumeUuid = UUID.fromString(resumeId);

        return ResumeInfoResponse.convertToResponse(
                updateResumeBasicUseCase.execute(userId, resumeUuid, request));
    }
}
