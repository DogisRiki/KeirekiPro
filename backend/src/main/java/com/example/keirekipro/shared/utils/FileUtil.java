package com.example.keirekipro.shared.utils;

import java.awt.image.BufferedImage;
import java.io.IOException;
import java.util.List;

import javax.imageio.ImageIO;

import org.springframework.web.multipart.MultipartFile;

/**
 * ファイル操作に関するユーティリティクラス
 */
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
}
