package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.CreateCareerRequest;
import com.example.keirekipro.presentation.resume.dto.ResumeInfoResponse;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.CreateCareerUseCase;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

import jakarta.validation.Valid;

/**
 * 職務経歴書 職歴新規作成コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class CreateCareerController {

    private final CreateCareerUseCase createCareerUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 職歴新規作成エンドポイント
     */
    @PostMapping("/{resumeId}/careers")
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "職務経歴書 職歴新規作成", description = "職務経歴書に職歴を新規作成する")
    public ResumeInfoResponse handle(
            @PathVariable("resumeId") UUID resumeId,
            @Valid @RequestBody CreateCareerRequest request) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        return ResumeInfoResponse.convertToResponse(
                createCareerUseCase.execute(userId, resumeId, request));
    }
}
