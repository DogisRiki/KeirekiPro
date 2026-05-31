package com.example.keirekipro.presentation.resume.dto;

import java.util.UUID;

import com.example.keirekipro.usecase.resume.command.UpdateSnsPlatformCommand;

import org.hibernate.validator.constraints.URL;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 職務経歴書 SNSプラットフォーム更新リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class UpdateSnsPlatformRequest {

    @NotBlank(message = "プラットフォーム名は入力必須です。")
    @Size(max = 50, message = "プラットフォーム名は50文字以内で入力してください。")
    private String name;

    @NotBlank(message = "リンクは入力必須です。")
    @URL(protocol = "https", message = "リンクはhttps形式のURLを指定してください。")
    @Size(max = 255, message = "リンクは255文字以内で入力してください。")
    private String link;

    /**
     * ユースケースコマンドへ変換する
     *
     * @param userId ユーザーID
     * @param resumeId 職務経歴書ID
     * @param snsPlatformId SNSプラットフォームID
     * @return SNSプラットフォーム更新コマンド
     */
    public UpdateSnsPlatformCommand toCommand(UUID userId, String resumeId, UUID snsPlatformId) {
        return new UpdateSnsPlatformCommand(userId, resumeId, snsPlatformId, name, link);
    }
}
