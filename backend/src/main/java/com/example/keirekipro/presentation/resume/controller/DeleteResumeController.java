package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.DeleteResumeUseCase;

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
 * 職務経歴書削除コントローラー
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/resumes")
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class DeleteResumeController {

    private final DeleteResumeUseCase deleteResumeUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 職務経歴書削除エンドポイント
     */
    @DeleteMapping("/{resumeId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "職務経歴書削除", description = "職務経歴書を削除する")
    public void handle(@PathVariable("resumeId") UUID resumeId) {
        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        deleteResumeUseCase.execute(userId, resumeId);
    }
}
