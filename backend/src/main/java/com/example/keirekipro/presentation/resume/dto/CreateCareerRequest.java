package com.example.keirekipro.presentation.resume.dto;

import java.time.YearMonth;
import java.util.UUID;

import com.example.keirekipro.presentation.shared.validator.YearMonthRange;
import com.example.keirekipro.usecase.resume.command.CreateCareerCommand;
import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonProperty;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 職務経歴書 職歴新規作成リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class CreateCareerRequest {

    @NotBlank(message = "会社名は入力必須です。")
    @Size(max = 50, message = "会社名は50文字以内で入力してください。")
    private String companyName;

    @NotNull(message = "開始年月は入力必須です。")
    @YearMonthRange(message = "開始年月が不正です。")
    @JsonFormat(pattern = "yyyy-MM")
    private YearMonth startDate;

    @YearMonthRange(message = "終了年月が不正です。")
    @JsonFormat(pattern = "yyyy-MM")
    private YearMonth endDate;

    @NotNull(message = "在籍中は入力必須です。")
    @JsonProperty("isActive")
    private Boolean active;

    /**
     * ユースケースコマンドへ変換する
     *
     * @param userId ユーザーID
     * @param resumeId 職務経歴書ID
     * @return 職歴作成コマンド
     */
    public CreateCareerCommand toCommand(UUID userId, String resumeId) {
        return new CreateCareerCommand(userId, resumeId, companyName, startDate, endDate, active);
    }
}
