package com.example.keirekipro.shared.utils;

import java.awt.image.BufferedImage;
import java.io.IOException;
import java.util.List;

import javax.imageio.ImageIO;

import org.springframework.web.multipart.MultipartFile;

import lombok.experimental.UtilityClass;

/**
 * ファイル操作に関するユーティリティクラス
 */
@UtilityClass
public class FileUtil {

    /**
     * ファイルサイズが最大サイズ以内かどうかをチェックする
     *
     * @param file        対象ファイル
     * @param maxFileSize 最大サイズ(バイト単位)
     * @return チェック結果 (制限内ならtrue / 超えていればfalse)
     */
    public static boolean isFileSizeValid(MultipartFile file, long maxFileSize) {
        return file.getSize() <= maxFileSize;
    }

    /**
     * 拡張子が許可されているかどうかをチェックする
     *
     * @param file              対象ファイル
     * @param allowedExtensions 許可する拡張子リスト
     * @return チェック結果 (許可する拡張子ならtrue / 許可されていない場合はfalse)
     */
    public static boolean isExtensionValid(MultipartFile file, List<String> allowedExtensions) {
        String originalFilename = file.getOriginalFilename();
        if (originalFilename == null || originalFilename.lastIndexOf(".") == -1) {
            return false;
        }
        String extension = originalFilename.substring(originalFilename.lastIndexOf(".") + 1).toLowerCase();
        return allowedExtensions.contains(extension);
    }

    /**
     * MIMEタイプが許可されているかどうかをチェックする
     *
     * @param file             対象ファイル
     * @param allowedMimeTypes 許可するMIMEタイプリスト
     * @return チェック結果 (許可するMIMEタイプならtrue / 許可されていない場合はfalse)
     */
    public static boolean isMimeTypeValid(MultipartFile file, List<String> allowedMimeTypes) {
        String mimeType = file.getContentType();
        return mimeType != null && allowedMimeTypes.contains(mimeType);
    }

    /**
     * ファイルを画像として正常に読み込めるかどうかをチェックする
     *
     * @param file 対象ファイル
     * @return チェック結果 (画像として読み込めればtrue / 読み込めなければfalse)
     */
    public static boolean isImageReadValid(MultipartFile file) {
        try {
            BufferedImage image = ImageIO.read(file.getInputStream());
            return image != null;
        } catch (IOException e) {
            return false;
        }
    }

    /**
     * ファイル名として安全な文字列に変換する
     * ファイル名は最大255文字とし、超える場合は切り捨てる
     *
     * @param raw         元のファイル名
     * @param defaultName nullまたは空白時のデフォルト名
     * @return サニタイズ後のファイル名
     */
    public static String sanitizeFileName(String raw, String defaultName) {
        String name = (raw == null || raw.isBlank()) ? defaultName : raw.trim();
        name = name.replaceAll("[\\\\/:*?\"<>|]", "_");
        name = name.replaceAll("[\\p{Cntrl}]", "");
        name = name.replaceAll("^_+$", ""); // アンダースコアのみの場合は空にする
        if (name.isBlank()) {
            return defaultName;
        }
        return name.length() > 255 ? name.substring(0, 255) : name;
    }
}
