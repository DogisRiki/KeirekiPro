package com.example.keirekipro.presentation.resume.dto;

import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 職務経歴書新規作成リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class CreateResumeRequest {

    @NotBlank(message = "職務経歴書名は入力必須です。")
    @Size(max = 50, message = "職務経歴書名は50文字以内で入力してください。")
    private String resumeName;

    private UUID resumeId;
}
