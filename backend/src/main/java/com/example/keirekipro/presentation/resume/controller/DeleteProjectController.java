package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.DeleteProjectUseCase;

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
 * 職務経歴書 プロジェクト削除コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class DeleteProjectController {

    private final DeleteProjectUseCase deleteProjectUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * プロジェクト削除エンドポイント
     */
    @DeleteMapping("/{resumeId}/projects/{projectId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "職務経歴書 プロジェクト削除", description = "職務経歴書のプロジェクトを削除する")
    public void handle(
            @PathVariable("resumeId") UUID resumeId,
            @PathVariable("projectId") UUID projectId) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        deleteProjectUseCase.execute(userId, resumeId, projectId);
    }
}
