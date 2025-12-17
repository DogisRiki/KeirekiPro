package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.GetResumeListResponse;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.GetResumeListUseCase;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書一覧取得コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class GetResumeListController {

    private final GetResumeListUseCase getResumeListUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 職務経歴書一覧取得エンドポイント
     */
    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "職務経歴書一覧取得", description = "職務経歴書一覧の取得を行う")
    public GetResumeListResponse handle() {
        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        return GetResumeListResponse.convertToResponse(getResumeListUseCase.execute(userId));
    }
}
