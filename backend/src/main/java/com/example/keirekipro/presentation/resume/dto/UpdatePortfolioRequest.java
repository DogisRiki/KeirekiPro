package com.example.keirekipro.presentation.resume.dto;

import java.util.UUID;

import com.example.keirekipro.usecase.resume.command.UpdatePortfolioCommand;

import org.hibernate.validator.constraints.URL;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 職務経歴書 ポートフォリオ更新リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class UpdatePortfolioRequest {

    @NotBlank(message = "ポートフォリオ名は入力必須です。")
    @Size(max = 50, message = "ポートフォリオ名は50文字以内で入力してください。")
    private String name;

    @NotBlank(message = "ポートフォリオ概要は入力必須です。")
    @Size(max = 1000, message = "ポートフォリオ概要は1000文字以内で入力してください。")
    private String overview;

    @Size(max = 1000, message = "技術スタックは1000文字以内で入力してください。")
    private String techStack;

    @NotBlank(message = "リンクは入力必須です。")
    @URL(protocol = "https", message = "リンクはhttps形式のURLを指定してください。")
    @Size(max = 255, message = "リンクは255文字以内で入力してください。")
    private String link;

    /**
     * ユースケースコマンドへ変換する
     *
     * @param userId ユーザーID
     * @param resumeId 職務経歴書ID
     * @param portfolioId ポートフォリオID
     * @return ポートフォリオ更新コマンド
     */
    public UpdatePortfolioCommand toCommand(UUID userId, String resumeId, UUID portfolioId) {
        return new UpdatePortfolioCommand(userId, resumeId, portfolioId, name, overview, techStack, link);
    }
}
