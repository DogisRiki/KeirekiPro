package com.example.keirekipro.presentation.resume.dto;

import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import com.fasterxml.jackson.annotation.JsonFormat;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 職務経歴書 資格更新リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class UpdateCertificationsRequest {

    @Valid
    private List<CertificationRequest> certifications;

    /**
     * 単一資格
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class CertificationRequest {

        private UUID id;

        @NotBlank(message = "資格名は入力必須です。")
        @Size(max = 50, message = "資格名は50文字以内で入力してください。")
        private String name;

        @NotNull(message = "取得年月は入力必須です。")
        @JsonFormat(pattern = "yyyy-MM")
        private YearMonth date;
    }
}
