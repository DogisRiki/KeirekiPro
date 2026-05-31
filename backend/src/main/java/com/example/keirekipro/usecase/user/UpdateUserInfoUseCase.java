package com.example.keirekipro.usecase.user;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.List;
import java.util.UUID;

import javax.imageio.ImageIO;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;
import com.example.keirekipro.usecase.shared.store.ObjectStore;
import com.example.keirekipro.usecase.shared.store.StoredObject;
import com.example.keirekipro.usecase.user.command.UpdateUserInfoCommand;
import com.example.keirekipro.usecase.user.command.UpdateUserInfoCommand.ProfileImageCommand;

import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.stereotype.Service;
import lombok.RequiredArgsConstructor;

/**
 * ユーザー情報更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateUserInfoUseCase {

    private final UserRepository userRepository;

    private final ObjectStore objectStore;

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
     * @param command コマンド
     */
    public void execute(UpdateUserInfoCommand command) {
        UUID userId = command.getUserId();

        ErrorCollector errorCollector = new ErrorCollector();

        // プロフィール画像のバリデーションチェック
        ProfileImageCommand profileImage = command.getProfileImage();
        validateProfileImage(profileImage, errorCollector);

        if (errorCollector.hasErrors()) {
            throw new UseCaseException(errorCollector.getErrors());
        }

        // ユーザー取得(ユーザーが存在しないのに更新リクエストはできない)
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AuthenticationCredentialsNotFoundException("不正なアクセスです。"));

        // オブジェクトストアへのアップロード（画像がある場合のみ）
        String imageKey = null;
        if (profileImage != null && !profileImage.isEmpty()) {
            String originalFilename = profileImage.getOriginalFilename();
            StoredObject object = new StoredObject(
                    profileImage.getContent(),
                    profileImage.getContentType(),
                    originalFilename);

            String extension = getExtension(originalFilename);
            String fileName = userId.toString() + (extension.isBlank() ? "" : "." + extension);

            imageKey = objectStore.putAs(object, "/profile/image/", fileName);
        }

        // ユーザー名更新
        if (command.getUsername() != null) {
            user = user.changeUsername(errorCollector, command.getUsername());
        }

        // プロフィール画像更新
        if (imageKey != null) {
            user = user.changeProfileImage(imageKey);
        }

        // 二段階認証設定更新
        user = user.changeTwoFactorAuthEnabled(errorCollector, command.isTwoFactorAuthEnabled());

        if (errorCollector.hasErrors()) {
            throw new UseCaseException(errorCollector.getErrors());
        }

        // 更新処理実行
        userRepository.save(user);
    }

    /**
     * プロフィール画像のバリデーションを行う
     *
     * @param file ファイル
     * @param errorCollector エラー収集
     */
    private void validateProfileImage(ProfileImageCommand file, ErrorCollector errorCollector) {
        if (file == null || file.isEmpty()) {
            return;
        }
        if (!ALLOWED_MIME_TYPES.contains(file.getContentType())) {
            errorCollector.addError("profileImage", "許可されていない画像形式です。");
        }
        if (!ALLOWED_EXTENSIONS.contains(getExtension(file.getOriginalFilename()))) {
            errorCollector.addError("profileImage", "許可されていないファイル形式です。jpg, jpeg, png, gifのみ許可されています。");
        }
        if (file.getSize() > ALLOWED_FILE_SIZE) {
            errorCollector.addError("profileImage", "プロフィール画像のサイズは1MB以下である必要があります。");
        }
        if (!isImageReadValid(file)) {
            errorCollector.addError("profileImage", "有効な画像ファイルではありません。");
        }
    }

    private boolean isImageReadValid(ProfileImageCommand file) {
        try {
            BufferedImage image = ImageIO.read(new ByteArrayInputStream(file.getContent()));
            return image != null;
        } catch (IOException e) {
            return false;
        }
    }

    private String getExtension(String originalFilename) {
        if (originalFilename == null) {
            return "";
        }
        int lastDot = originalFilename.lastIndexOf(".");
        if (lastDot == -1 || lastDot == originalFilename.length() - 1) {
            return "";
        }
        return originalFilename.substring(lastDot + 1).toLowerCase();
    }
}
