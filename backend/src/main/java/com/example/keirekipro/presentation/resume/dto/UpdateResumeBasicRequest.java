package com.example.keirekipro.presentation.resume.dto;

import java.time.LocalDate;

import com.example.keirekipro.presentation.shared.validator.LocalDateRange;

import org.springframework.format.annotation.DateTimeFormat;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 職務経歴書 基本情報更新リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class UpdateResumeBasicRequest {

    @NotBlank(message = "職務経歴書名は入力必須です。")
    @Size(max = 50, message = "職務経歴書名は50文字以内で入力してください。")
    private String resumeName;

    @NotNull(message = "日付は入力必須です。")
    @LocalDateRange(message = "日付が不正です。")
    @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
    private LocalDate date;

    @NotBlank(message = "姓は入力必須です。")
    @Size(max = 10, message = "姓は10文字以内で入力してください。")
    private String lastName;

    @NotBlank(message = "名は入力必須です。")
    @Size(max = 10, message = "名は10文字以内で入力してください。")
    private String firstName;
}
