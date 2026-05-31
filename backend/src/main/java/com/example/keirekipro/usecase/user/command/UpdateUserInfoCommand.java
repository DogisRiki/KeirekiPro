package com.example.keirekipro.usecase.user.command;

import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * ユーザー情報更新ユースケースの入力コマンド
 */
@Data
@AllArgsConstructor
public class UpdateUserInfoCommand {

    private UUID userId;

    private String username;

    private ProfileImageCommand profileImage;

    private boolean twoFactorAuthEnabled;

    /**
     * Multipart型から切り離したプロフィール画像データ
     */
    @Data
    @AllArgsConstructor
    public static class ProfileImageCommand {

        private byte[] content;

        private String contentType;

        private String originalFilename;

        public boolean isEmpty() {
            return content == null || content.length == 0;
        }

        public long getSize() {
            return content == null ? 0 : content.length;
        }
    }
}
