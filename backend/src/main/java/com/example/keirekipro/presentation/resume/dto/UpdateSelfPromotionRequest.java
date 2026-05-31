package com.example.keirekipro.presentation.resume.dto;

import java.util.UUID;

import com.example.keirekipro.usecase.resume.command.UpdateSelfPromotionCommand;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 職務経歴書 自己PR更新リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class UpdateSelfPromotionRequest {

    @NotBlank(message = "タイトルは入力必須です。")
    @Size(max = 50, message = "タイトルは50文字以内で入力してください。")
    private String title;

    @NotBlank(message = "コンテンツは入力必須です。")
    @Size(max = 1000, message = "コンテンツは1000文字以内で入力してください。")
    private String content;

    /**
     * ユースケースコマンドへ変換する
     *
     * @param userId ユーザーID
     * @param resumeId 職務経歴書ID
     * @param selfPromotionId 自己PRID
     * @return 自己PR更新コマンド
     */
    public UpdateSelfPromotionCommand toCommand(UUID userId, String resumeId, UUID selfPromotionId) {
        return new UpdateSelfPromotionCommand(userId, resumeId, selfPromotionId, title, content);
    }
}
