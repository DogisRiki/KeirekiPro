package com.example.keirekipro.presentation.user.dto;

import java.io.IOException;
import java.util.UUID;

import com.example.keirekipro.usecase.user.command.UpdateUserInfoCommand;
import com.example.keirekipro.usecase.user.command.UpdateUserInfoCommand.ProfileImageCommand;

import org.springframework.web.multipart.MultipartFile;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * ユーザー情報更新リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class UpdateUserInfoRequest {

    private String username;

    private MultipartFile profileImage;

    private boolean twoFactorAuthEnabled;

    /**
     * ユースケースコマンドへ変換する
     *
     * @param userId ユーザーID
     * @return ユーザー情報更新コマンド
     * @throws IOException プロフィール画像を読み込めない場合
     */
    public UpdateUserInfoCommand toCommand(UUID userId) throws IOException {
        ProfileImageCommand profileImageCommand = null;
        if (profileImage != null) {
            profileImageCommand = new ProfileImageCommand(
                    profileImage.getBytes(),
                    profileImage.getContentType(),
                    profileImage.getOriginalFilename());
        }
        return new UpdateUserInfoCommand(userId, username, profileImageCommand, twoFactorAuthEnabled);
    }
}
