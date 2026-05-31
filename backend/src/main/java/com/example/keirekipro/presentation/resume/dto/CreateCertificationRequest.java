package com.example.keirekipro.presentation.resume.dto;

import java.time.YearMonth;
import java.util.UUID;

import com.example.keirekipro.presentation.shared.validator.YearMonthRange;
import com.example.keirekipro.usecase.resume.command.CreateCertificationCommand;
import com.fasterxml.jackson.annotation.JsonFormat;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 職務経歴書 資格新規作成リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class CreateCertificationRequest {

    @NotBlank(message = "資格名は入力必須です。")
    @Size(max = 50, message = "資格名は50文字以内で入力してください。")
    private String name;

    @NotNull(message = "取得年月は入力必須です。")
    @YearMonthRange(message = "取得年月が不正です。")
    @JsonFormat(pattern = "yyyy-MM")
    private YearMonth date;

    /**
     * ユースケースコマンドへ変換する
     *
     * @param userId ユーザーID
     * @param resumeId 職務経歴書ID
     * @return 資格作成コマンド
     */
    public CreateCertificationCommand toCommand(UUID userId, String resumeId) {
        return new CreateCertificationCommand(userId, resumeId, name, date);
    }
}
