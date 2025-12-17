package com.example.keirekipro.presentation.resume.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.resume.dto.ResumeInfoResponse;
import com.example.keirekipro.presentation.resume.dto.UpdateCertificationRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.resume.UpdateCertificationUseCase;

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
 * 職務経歴書 資格更新コントローラー
 */
@RestController
@RequestMapping("/api/resumes")
@RequiredArgsConstructor
@Tag(name = "resumes", description = "職務経歴書に関するエンドポイント")
public class UpdateCertificationController {

    private final UpdateCertificationUseCase updateCertificationUseCase;

    private final CurrentUserFacade currentUserFacade;

    /**
     * 資格更新エンドポイント
     */
    @PutMapping("/{resumeId}/certifications/{certificationId}")
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "職務経歴書 資格更新", description = "職務経歴書の資格を更新する")
    public ResumeInfoResponse handle(
            @PathVariable("resumeId") UUID resumeId,
            @PathVariable("certificationId") UUID certificationId,
            @Valid @RequestBody UpdateCertificationRequest request) {

        UUID userId = UUID.fromString(currentUserFacade.getUserId());

        return ResumeInfoResponse.convertToResponse(
                updateCertificationUseCase.execute(userId, resumeId, certificationId, request));
    }
}
