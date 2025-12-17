package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.ResumeInfoResponse;
import com.example.keirekipro.presentation.resume.dto.UpdatePortfolioRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.UpdatePortfolioUseCase;

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
 * 職務経歴書 ポートフォリオ更新コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class UpdatePortfolioController {

    private final UpdatePortfolioUseCase updatePortfolioUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * ポートフォリオ更新エンドポイント
     */
    @PutMapping("/{resumeId}/portfolios/{portfolioId}")
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "職務経歴書 ポートフォリオ更新", description = "職務経歴書のポートフォリオを更新する")
    public ResumeInfoResponse handle(
            @PathVariable("resumeId") UUID resumeId,
            @PathVariable("portfolioId") UUID portfolioId,
            @Valid @RequestBody UpdatePortfolioRequest request) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        return ResumeInfoResponse.convertToResponse(
                updatePortfolioUseCase.execute(userId, resumeId, portfolioId, request));
    }
}
