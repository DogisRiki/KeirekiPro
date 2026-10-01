package com.example.keirekipro.usecase.user;

import java.util.List;
import java.util.UUID;

/**
 * プロフィール画像の保存先キーの命名規則
 */
public final class ProfileImageKeys {

    /**
     * 保存プレフィックス
     */
    public static final String PREFIX = "/profile/image/";

    /**
     * 許可するファイル拡張子
     */
    public static final List<String> ALLOWED_EXTENSIONS = List.of("jpg", "jpeg", "png", "gif");

    private ProfileImageKeys() {
    }

    /**
     * 保存ファイル名を返す（ユーザーID + 拡張子）
     *
     * @param userId ユーザーID
     * @param extension 拡張子（ドットなし。空の場合は付けない）
     * @return 保存ファイル名
     */
    public static String fileName(UUID userId, String extension) {
        return userId.toString() + (extension.isBlank() ? "" : "." + extension);
    }

    /**
     * ユーザーのプロフィール画像が取り得るキーをすべて返す
     * 拡張子の違う画像に替えると以前の画像が別のキーで残るため、許可する拡張子ごとのキーを返す
     *
     * @param userId ユーザーID
     * @return キーの一覧
     */
    public static List<String> keysOf(UUID userId) {
        return ALLOWED_EXTENSIONS.stream()
                .map(extension -> PREFIX + fileName(userId, extension))
                .toList();
    }
}
