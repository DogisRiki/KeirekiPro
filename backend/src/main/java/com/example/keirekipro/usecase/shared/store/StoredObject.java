package com.example.keirekipro.usecase.shared.store;

/**
 * オブジェクトストアへ保存するデータ
 *
 * @param bytes            バイト配列
 * @param contentType      Content-Type
 * @param originalFilename 元のファイル名
 */
public record StoredObject(
        byte[] bytes,
        String contentType,
        String originalFilename) {
}
