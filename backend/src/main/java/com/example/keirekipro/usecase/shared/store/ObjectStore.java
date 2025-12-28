package com.example.keirekipro.usecase.shared.store;

import java.time.Duration;

/**
 * オブジェクトストア操作ポート
 */
public interface ObjectStore {

    /**
     * オブジェクトを保存し、保存先キーを返す
     *
     * @param object    保存対象
     * @param keyPrefix 保存プレフィックス（末尾に/必須）
     * @return 保存されたキー
     */
    String put(StoredObject object, String keyPrefix);

    /**
     * 任意のファイル名を指定して保存し、保存先キーを返す
     *
     * @param object    保存対象
     * @param keyPrefix 保存プレフィックス（末尾に/必須）
     * @param fileName  保存ファイル名（拡張子含む）
     * @return 保存されたキー
     */
    String putAs(StoredObject object, String keyPrefix, String fileName);

    /**
     * バイト配列として取得する
     *
     * @param key オブジェクトキー
     * @return バイト配列
     */
    byte[] getBytes(String key);

    /**
     * オブジェクトを削除する
     *
     * @param key オブジェクトキー
     */
    void delete(String key);

    /**
     * 取得用URLを発行する
     *
     * @param key オブジェクトキー
     * @param ttl 有効期限
     * @return 取得用URL
     */
    String issueGetUrl(String key, Duration ttl);
}
