package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.DeleteSelfPromotionUseCase;

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
 * 職務経歴書 自己PR削除コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class DeleteSelfPromotionController {

    private final DeleteSelfPromotionUseCase deleteSelfPromotionUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 自己PR削除エンドポイント
     */
    @DeleteMapping("/{resumeId}/self-promotions/{selfPromotionId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "職務経歴書 自己PR削除", description = "職務経歴書の自己PRを削除する")
    public void handle(
            @PathVariable("resumeId") UUID resumeId,
            @PathVariable("selfPromotionId") UUID selfPromotionId) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        deleteSelfPromotionUseCase.execute(userId, resumeId, selfPromotionId);
    }
}
