package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.ResumeInfoResponse;
import com.example.keirekipro.presentation.resume.dto.UpdateProjectRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.UpdateProjectUseCase;

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
 * 職務経歴書 プロジェクト更新コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class UpdateProjectController {

    private final UpdateProjectUseCase updateProjectUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * プロジェクト更新エンドポイント
     */
    @PutMapping("/{resumeId}/projects/{projectId}")
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "職務経歴書 プロジェクト更新", description = "職務経歴書のプロジェクトを更新する")
    public ResumeInfoResponse handle(
            @PathVariable("resumeId") UUID resumeId,
            @PathVariable("projectId") UUID projectId,
            @Valid @RequestBody UpdateProjectRequest request) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        return ResumeInfoResponse.convertToResponse(
                updateProjectUseCase.execute(userId, resumeId, projectId, request));
    }
}
