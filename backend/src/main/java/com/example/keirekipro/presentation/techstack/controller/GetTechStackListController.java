package com.example.keirekipro.presentation.techstack.controller;

import com.example.keirekipro.presentation.techstack.dto.TechStackListResponse;
import com.example.keirekipro.usecase.query.techstack.GetTechStackListQueryService;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

/**
 * 技術スタック一覧取得コントローラー
 */
@RestController
@RequestMapping("/api/tech-stacks")
@RequiredArgsConstructor
@Tag(name = "techstacks", description = "技術スタックに関するエンドポイント")
public class GetTechStackListController {

    private final GetTechStackListQueryService getTechStackListQueryService;

    /**
     * 技術スタック一覧取得エンドポイント
     */
    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "技術スタック一覧の取得", description = "画面入力補助用の技術スタック一覧を取得する")
    public TechStackListResponse handle() {
        return TechStackListResponse.convertFrom(getTechStackListQueryService.execute());
    }
}
