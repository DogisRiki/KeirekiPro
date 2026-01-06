package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.RestoreResumeRequest;
import com.example.keirekipro.presentation.resume.dto.ResumeInfoResponse;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.RestoreResumeUseCase;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

import jakarta.validation.Valid;

/**
 * 職務経歴書リストアコントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class RestoreResumeController {

    private final RestoreResumeUseCase restoreResumeUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 職務経歴書リストアエンドポイント
     *
     * @param request リクエスト
     * @return リストアされた職務経歴書情報
     */
    @PostMapping("/restore")
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "職務経歴書リストア", description = "JSON形式のバックアップファイルから職務経歴書をリストアする")
    public ResumeInfoResponse handle(@Valid @RequestBody RestoreResumeRequest request) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        return ResumeInfoResponse.convertToResponse(restoreResumeUseCase.execute(userId, request));
    }
}
