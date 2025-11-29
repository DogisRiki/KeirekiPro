package com.example.keirekipro.presentation.resume.dto;

import java.util.List;
import java.util.UUID;

import org.hibernate.validator.constraints.URL;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 職務経歴書 ソーシャルリンク更新リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class UpdateSocialLinksRequest {

    @Valid
    private List<SocialLinkRequest> socialLinks;

    /**
     * 単一ソーシャルリンク
     */
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class SocialLinkRequest {

        private UUID id;

        @NotBlank(message = "ソーシャル名は入力必須です。")
        @Size(max = 50, message = "ソーシャル名は50文字以内で入力してください。")
        private String name;

        @NotBlank(message = "リンクは入力必須です。")
        @URL(protocol = "https", message = "リンクはhttps形式のURLを指定してください。")
        @Size(max = 255, message = "リンクは255文字以内で入力してください。")
        private String link;
    }
}
