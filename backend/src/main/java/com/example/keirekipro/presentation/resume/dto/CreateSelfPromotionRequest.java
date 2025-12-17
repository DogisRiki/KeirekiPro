package com.example.keirekipro.presentation.resume.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 職務経歴書 自己PR新規作成リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class CreateSelfPromotionRequest {

    @NotBlank(message = "タイトルは入力必須です。")
    @Size(max = 50, message = "タイトルは50文字以内で入力してください。")
    private String title;

    @NotBlank(message = "コンテンツは入力必須です。")
    @Size(max = 1000, message = "コンテンツは1000文字以内で入力してください。")
    private String content;
}
