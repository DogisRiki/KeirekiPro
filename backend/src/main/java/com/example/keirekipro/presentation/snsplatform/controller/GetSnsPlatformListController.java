package com.example.keirekipro.presentation.snsplatform.controller;

import com.example.keirekipro.presentation.snsplatform.dto.SnsPlatformListResponse;
import com.example.keirekipro.usecase.query.snsplatform.GetSnsPlatformListQueryService;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * SNSプラットフォーム一覧取得コントローラー
 */
@RestController
@RequestMapping("/api/sns-platforms")
@RequiredArgsConstructor
@Tag(name = "snsplatforms", description = "SNSプラットフォームに関するエンドポイント")
public class GetSnsPlatformListController {

    private final GetSnsPlatformListQueryService getSnsPlatformListQueryService;

    /**
     * SNSプラットフォーム一覧取得エンドポイント
     */
    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "SNSプラットフォーム一覧の取得", description = "画面入力補助用のSNSプラットフォーム一覧を取得する")
    public SnsPlatformListResponse handle() {
        return SnsPlatformListResponse.convertFrom(getSnsPlatformListQueryService.execute());
    }
}
