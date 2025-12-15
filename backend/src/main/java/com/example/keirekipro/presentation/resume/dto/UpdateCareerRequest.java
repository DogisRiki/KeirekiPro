package com.example.keirekipro.presentation.resume.dto;

import java.time.YearMonth;

import com.fasterxml.jackson.annotation.JsonFormat;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 職務経歴書 職歴更新リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class UpdateCareerRequest {

    @NotBlank(message = "会社名は入力必須です。")
    @Size(max = 50, message = "会社名は50文字以内で入力してください。")
    private String companyName;

    @NotNull(message = "開始年月は入力必須です。")
    @JsonFormat(pattern = "yyyy-MM")
    private YearMonth startDate;

    @JsonFormat(pattern = "yyyy-MM")
    private YearMonth endDate;

    @NotNull(message = "在籍中は入力必須です。")
    private Boolean isActive;
}
