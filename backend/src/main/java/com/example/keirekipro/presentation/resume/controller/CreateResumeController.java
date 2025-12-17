package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.CreateResumeRequest;
import com.example.keirekipro.presentation.resume.dto.ResumeInfoResponse;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.CopyCreateResumeUseCase;
import com.example.keirekipro.usecase.resume.CreateResumeUseCase;

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
 * 職務経歴書新規作成コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class CreateResumeController {

    private final CreateResumeUseCase createResumeUseCase;

    private final CopyCreateResumeUseCase copyCreateResumeUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 職務経歴書新規作成エンドポイント
     */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "職務経歴書新規作成", description = "職務経歴書の新規作成を行う")
    public ResumeInfoResponse handle(@Valid @RequestBody CreateResumeRequest request) {
        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        if (request.getResumeId() == null) {
            return ResumeInfoResponse.convertToResponse(createResumeUseCase.execute(userId, request));
        } else {
            return ResumeInfoResponse.convertToResponse(copyCreateResumeUseCase.execute(userId, request));
        }
    }
}
