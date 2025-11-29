package com.example.keirekipro.presentation.resume.dto;

import java.util.List;
import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 職務経歴書 自己PR更新リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class UpdateSelfPromotionsRequest {

    @Valid
    private List<SelfPromotionRequest> selfPromotions;

    /**
     * 単一自己PR
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class SelfPromotionRequest {

        private UUID id;

        @NotBlank(message = "タイトルは入力必須です。")
        @Size(max = 50, message = "タイトルは50文字以内で入力してください。")
        private String title;

        @NotBlank(message = "コンテンツは入力必須です。")
        @Size(max = 1000, message = "コンテンツは1000文字以内で入力してください。")
        private String content;
    }
}
