package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.ResumeInfoResponse;
import com.example.keirekipro.presentation.resume.dto.UpdateCareerRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.UpdateCareerUseCase;

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
 * 職務経歴書 職歴更新コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class UpdateCareerController {

    private final UpdateCareerUseCase updateCareerUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 職歴更新エンドポイント
     */
    @PutMapping("/{resumeId}/careers/{careerId}")
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "職務経歴書 職歴更新", description = "職務経歴書の職歴を更新する")
    public ResumeInfoResponse handle(
            @PathVariable("resumeId") UUID resumeId,
            @PathVariable("careerId") UUID careerId,
            @Valid @RequestBody UpdateCareerRequest request) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        return ResumeInfoResponse.convertToResponse(
                updateCareerUseCase.execute(userId, resumeId, careerId, request));
    }
}
