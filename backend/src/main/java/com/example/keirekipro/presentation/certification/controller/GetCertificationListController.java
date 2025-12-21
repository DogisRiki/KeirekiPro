package com.example.keirekipro.presentation.certification.controller;

import com.example.keirekipro.presentation.certification.dto.CertificationListResponse;
import com.example.keirekipro.usecase.query.certification.GetCertificationListQueryService;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * 資格一覧取得コントローラー
 */
@RestController
@RequestMapping("/api/certifications")
@RequiredArgsConstructor
@Tag(name = "certifications", description = "資格に関するエンドポイント")
public class GetCertificationListController {

    private final GetCertificationListQueryService getCertificationListQueryService;

    /**
     * 資格一覧取得エンドポイント
     */
    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "資格一覧の取得", description = "画面入力補助用の資格一覧を取得する")
    public CertificationListResponse handle() {
        return CertificationListResponse.convertFrom(getCertificationListQueryService.execute());
    }
}
