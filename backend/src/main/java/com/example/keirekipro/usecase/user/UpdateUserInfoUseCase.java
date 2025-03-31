package com.example.keirekipro.usecase.user;

import java.io.IOException;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.infrastructure.repository.user.dto.UserInfo;
import com.example.keirekipro.infrastructure.repository.user.mapper.UserMapper;
import com.example.keirekipro.infrastructure.shared.aws.AwsS3Client;
import com.example.keirekipro.presentation.user.dto.UpdateUserInfoRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.shared.utils.FileUtil;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;
import com.example.keirekipro.usecase.user.dto.UpdateUserInfoUseCaseDto;

import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー情報更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateUserInfoUseCase {

    private final UserMapper userMapper;

    private final AwsS3Client awsS3Client;

    /**
     * 許可する最大ファイルサイズ(Byte)
     */
    private static final long ALLOWED_FILE_SIZE = 1024 * 1024;

    /**
     * 許可するMIMEタイプ
     */
    private static final List<String> ALLOWED_MIME_TYPES = List.of("image/jpeg", "image/png", "image/gif");

    /**
     * 許可するファイル拡張子
     */
    private static final List<String> ALLOWED_EXTENSIONS = List.of("jpg", "jpeg", "png", "gif");

    /**
     * ユーザー情報更新ユースケースを実行する
     *
     * @param request リクエスト
     * @param userId  ユーザーID
     */
    public UpdateUserInfoUseCaseDto execute(UpdateUserInfoRequest request, UUID userId) {

        Notification notification = new Notification();

        // ユーザー名のバリデーションチェック
        if (request.getUsername() != null) {
            String trimmed = request.getUsername().strip();
            if (trimmed.isEmpty()) {
                notification.addError("username", "ユーザー名は入力必須です。");
            } else if (trimmed.length() > 50) {
                notification.addError("username", "ユーザー名は50文字以内で入力してください。");
            }
        }

        // プロフィール画像のバリデーションチェック
        MultipartFile profileImage = request.getProfileImage();
        if (profileImage != null && !profileImage.isEmpty()) {
            if (!FileUtil.isMimeTypeValid(profileImage, ALLOWED_MIME_TYPES)) {
                notification.addError("profileImage", "許可されていない画像形式です。");
            }
            if (!FileUtil.isExtensionValid(profileImage, ALLOWED_EXTENSIONS)) {
                notification.addError("profileImage", "許可されていないファイル形式です。jpg, jpeg, png, gifのみ許可されています。");
            }
            if (!FileUtil.isFileSizeValid(profileImage, ALLOWED_FILE_SIZE)) {
                notification.addError("profileImage", "プロフィール画像のサイズは1MB以下である必要があります。");
            }
            if (!FileUtil.isImageReadValid(profileImage)) {
                notification.addError("profileImage", "有効な画像ファイルではありません。");
            }
        }

        // エラーチェック
        if (notification.hasErrors()) {
            throw new UseCaseException(notification.getErrors());
        }

        // S3へのアップロード（画像がある場合のみ）
        String key = null;
        byte[] profileImageFile = null;
        if (profileImage != null && !profileImage.isEmpty()) {
            try {
                key = awsS3Client.uploadFile(profileImage, "/profile/image");
                profileImageFile = profileImage.getBytes();
            } catch (IOException e) {
                throw new UseCaseException("プロフィール画像のアップロードに失敗しました。しばらく時間を置いてから再度お試しください。");
            }
        }

        // ユーザー情報更新
        UserInfo userInfo = userMapper.update(userId, request.getUsername(), key,
                request.isTwoFactorAuthEnabled()).orElseThrow(() -> new UseCaseException("a"));

        return UpdateUserInfoUseCaseDto.builder()
                .id(userInfo.getId())
                .username(userInfo.getUsername())
                .profileImage(profileImageFile)
                .twoFactorAuthEnabled(userInfo.isTwoFactorAuthEnabled())
                .build();
    }
}
