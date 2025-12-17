package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.CreateProjectRequest;
import com.example.keirekipro.presentation.resume.dto.ResumeInfoResponse;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.CreateProjectUseCase;

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
 * 職務経歴書 プロジェクト新規作成コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class CreateProjectController {

    private final CreateProjectUseCase createProjectUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * プロジェクト新規作成エンドポイント
     */
    @PostMapping("/{resumeId}/projects")
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "職務経歴書 プロジェクト新規作成", description = "職務経歴書にプロジェクトを新規作成する")
    public ResumeInfoResponse handle(
            @PathVariable("resumeId") UUID resumeId,
            @Valid @RequestBody CreateProjectRequest request) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        return ResumeInfoResponse.convertToResponse(
                createProjectUseCase.execute(userId, resumeId, request));
    }
}
