package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.ResumeInfoResponse;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.GetResumeInfoUseCase;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書情報取得コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class GetResumeInfoController {

    private final GetResumeInfoUseCase getResumeInfoUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 職務経歴書情報取得エンドポイント
     */
    @GetMapping("/{resumeId}")
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "職務経歴書情報の取得", description = "単一の職務経歴書情報の取得を行う")
    public ResumeInfoResponse handle(@PathVariable("resumeId") String resumeId) {
        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        return ResumeInfoResponse.convertToResponse(getResumeInfoUseCase.execute(userId, UUID.fromString(resumeId)));
    }
}
