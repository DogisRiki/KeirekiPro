package com.example.keirekipro.usecase.user;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Iterator;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;

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
     * 許可する画像の幅と高さの上限(ピクセル)
     */
    private static final int MAX_IMAGE_DIMENSION = 4096;

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
            String fileName = ProfileImageKeys.fileName(userId, extension);

            imageKey = objectStore.putAs(object, ProfileImageKeys.PREFIX, fileName);
        }

        // ユーザー名更新
        if (command.getUsername() != null) {
            user = user.changeUsername(errorCollector, command.getUsername());
        }

        // プロフィール画像更新
        if (imageKey != null) {
            user = user.changeProfileImage(imageKey);
        }

        // 二段階認証設定更新(指定がない場合は現在の設定を維持する)
        if (command.getTwoFactorAuthEnabled() != null) {
            user = user.changeTwoFactorAuthEnabled(errorCollector, command.getTwoFactorAuthEnabled());
        }

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
        if (!ProfileImageKeys.ALLOWED_EXTENSIONS.contains(getExtension(file.getOriginalFilename()))) {
            errorCollector.addError("profileImage", "許可されていないファイル形式です。jpg, jpeg, png, gifのみ許可されています。");
        }
        if (file.getSize() > ALLOWED_FILE_SIZE) {
            errorCollector.addError("profileImage", "プロフィール画像のサイズは1MB以下である必要があります。");
        }
        validateImageContent(file, errorCollector);
    }

    /**
     * 画像の中身を読み込む前に幅と高さを確かめ、上限以内のときだけ中身を読み込めるかを確かめる
     *
     * @param file ファイル
     * @param errorCollector エラー収集オブジェクト
     */
    private void validateImageContent(ProfileImageCommand file, ErrorCollector errorCollector) {
        Optional<ImageSize> size = readImageSize(file.getContent());
        if (size.isEmpty()) {
            errorCollector.addError("profileImage", "有効な画像ファイルではありません。");
            return;
        }
        if (size.get().width() > MAX_IMAGE_DIMENSION || size.get().height() > MAX_IMAGE_DIMENSION) {
            errorCollector.addError("profileImage", "プロフィール画像の幅と高さは4096ピクセル以下である必要があります。");
            return;
        }
        if (!isImageReadValid(file)) {
            errorCollector.addError("profileImage", "有効な画像ファイルではありません。");
        }
    }

    /**
     * 画像のヘッダだけを読み、幅と高さを取得する
     *
     * @param content 画像のバイト列
     * @return 幅と高さ。画像として読めない場合は空
     */
    private Optional<ImageSize> readImageSize(byte[] content) {
        try (ImageInputStream input = ImageIO.createImageInputStream(new ByteArrayInputStream(content))) {
            if (input == null) {
                return Optional.empty();
            }
            Iterator<ImageReader> readers = ImageIO.getImageReaders(input);
            if (!readers.hasNext()) {
                return Optional.empty();
            }
            ImageReader reader = readers.next();
            try {
                reader.setInput(input, true, true);
                return Optional.of(new ImageSize(reader.getWidth(0), reader.getHeight(0)));
            } finally {
                reader.dispose();
            }
        } catch (IOException e) {
            return Optional.empty();
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

    private record ImageSize(int width, int height) {
    }
}
