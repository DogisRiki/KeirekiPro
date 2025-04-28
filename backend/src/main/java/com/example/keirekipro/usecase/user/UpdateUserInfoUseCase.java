package com.example.keirekipro.usecase.user;

import java.io.IOException;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.infrastructure.shared.aws.AwsS3Client;
import com.example.keirekipro.presentation.user.dto.UpdateUserInfoRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.shared.utils.FileUtil;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;
import com.example.keirekipro.usecase.user.dto.UpdateUserInfoUseCaseDto;

import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー情報更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateUserInfoUseCase {

    private final UserRepository userRepository;

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
     * @return 更新後のユーザー情報 DTO
     */
    public UpdateUserInfoUseCaseDto execute(UpdateUserInfoRequest request, UUID userId) {

        Notification notification = new Notification();

        // プロフィール画像のバリデーションチェック
        MultipartFile profileImage = request.getProfileImage();
        validateProfileImage(profileImage, notification);

        if (notification.hasErrors()) {
            throw new UseCaseException(notification.getErrors());
        }

        // ユーザー取得(ユーザーが存在しないのに更新リクエストはできない)
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AccessDeniedException("不正なアクセスです。"));

        // S3へのアップロード（画像がある場合のみ）
        String imageKey = null;
        byte[] profileImageFile = null;
        if (profileImage != null && !profileImage.isEmpty()) {
            try {
                imageKey = awsS3Client.uploadFile(profileImage, "/profile/image/");
                profileImageFile = profileImage.getBytes();
            } catch (IOException e) {
                throw new UseCaseException("プロフィール画像のアップロードに失敗しました。しばらく時間を置いてから再度お試しください。");
            }
        }

        // ユーザー名更新
        if (request.getUsername() != null) {
            user = user.changeUsername(notification, request.getUsername());
        }

        // プロフィール画像更新
        if (imageKey != null) {
            user = user.changeProfileImage(imageKey);
        }

        // 二段階認証設定更新
        user = user.changeTwoFactorAuthEnabled(notification, request.isTwoFactorAuthEnabled());

        if (notification.hasErrors()) {
            throw new UseCaseException(notification.getErrors());
        }

        // 更新処理実行
        userRepository.save(user);

        return UpdateUserInfoUseCaseDto.builder()
                .id(user.getId())
                .username(user.getUsername())
                .profileImage(profileImageFile)
                .twoFactorAuthEnabled(user.isTwoFactorAuthEnabled())
                .build();
    }

    private void validateProfileImage(MultipartFile file, Notification notification) {
        if (file == null || file.isEmpty()) {
            return;
        }
        if (!FileUtil.isMimeTypeValid(file, ALLOWED_MIME_TYPES)) {
            notification.addError("profileImage", "許可されていない画像形式です。");
        }
        if (!FileUtil.isExtensionValid(file, ALLOWED_EXTENSIONS)) {
            notification.addError("profileImage", "許可されていないファイル形式です。jpg, jpeg, png, gifのみ許可されています。");
        }
        if (!FileUtil.isFileSizeValid(file, ALLOWED_FILE_SIZE)) {
            notification.addError("profileImage", "プロフィール画像のサイズは1MB以下である必要があります。");
        }
        if (!FileUtil.isImageReadValid(file)) {
            notification.addError("profileImage", "有効な画像ファイルではありません。");
        }
    }
}
